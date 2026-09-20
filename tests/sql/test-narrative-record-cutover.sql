-- Task 7 atomic cutover contract. Run only on a disposable PostgreSQL 17 database.

BEGIN;

DO $cutover_structure$
DECLARE
  v_actual text[];
  v_role text;
  v_definition text;
  v_required_locks text[];
  v_actual_locks text[];
  v_lock_tail text;
  v_lock_end integer;
BEGIN
  IF to_regclass('private.narrative_record_cutover_receipt') IS NULL THEN
    RAISE EXCEPTION 'CUTOVER_RECEIPT_TABLE_MISSING';
  END IF;
  IF to_regclass('private.narrative_record_contract') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT_STATE_TABLE_MISSING';
  END IF;
  IF to_regprocedure(
    'private.apply_narrative_record_cutover(text,text,text,text,text,text,uuid,text,text)'
  ) IS NULL THEN
    RAISE EXCEPTION 'CUTOVER_KERNEL_MISSING';
  END IF;
  IF to_regprocedure('private.narrative_legacy_candidate_publication_state(bigint,bigint,uuid)')
     IS NULL THEN
    RAISE EXCEPTION 'LEGACY_CANDIDATE_PROJECTOR_MISSING';
  END IF;
  IF to_regprocedure('private.apply_narrative_record_contract_acl(integer)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT_ACL_SOURCE_OF_TRUTH_MISSING';
  END IF;

  SELECT array_agg(attribute.attname ORDER BY attribute.attnum)
    INTO v_actual
    FROM pg_attribute attribute
   WHERE attribute.attrelid='private.narrative_record_cutover_receipt'::regclass
     AND attribute.attnum>0 AND NOT attribute.attisdropped;
  IF v_actual IS DISTINCT FROM ARRAY[
    'nonce','record_candidates_sha256','legacy_candidates_sha256',
    'record_manifest_sha256','legacy_manifest_sha256','inventory_sha256',
    'approval_sha256','database_name','system_identifier','sequence_before',
    'sequence_floor','sequence_after','result','result_sha256','committed_at'
  ]::text[] THEN
    RAISE EXCEPTION 'CUTOVER_RECEIPT_COLUMNS_INVALID: %',v_actual;
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class
           WHERE oid='private.narrative_record_cutover_receipt'::regclass) THEN
    RAISE EXCEPTION 'CUTOVER_RECEIPT_RLS_DISABLED';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy
              WHERE polrelid='private.narrative_record_cutover_receipt'::regclass) THEN
    RAISE EXCEPTION 'CUTOVER_RECEIPT_POLICY_LEAK';
  END IF;
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_table_privilege(v_role,'private.narrative_record_cutover_receipt','SELECT')
       OR has_table_privilege(v_role,'private.narrative_record_cutover_receipt','INSERT')
       OR has_table_privilege(v_role,'private.narrative_record_cutover_receipt','UPDATE')
       OR has_table_privilege(v_role,'private.narrative_record_cutover_receipt','DELETE') THEN
      RAISE EXCEPTION 'CUTOVER_RECEIPT_PRIVILEGE_LEAK: %',v_role;
    END IF;
    IF has_function_privilege(
      v_role,
      'private.apply_narrative_record_cutover(text,text,text,text,text,text,uuid,text,text)'::regprocedure,
      'EXECUTE'
    ) THEN
      RAISE EXCEPTION 'CUTOVER_KERNEL_PRIVILEGE_LEAK: %',v_role;
    END IF;
  END LOOP;
  SELECT pg_get_functiondef(
    'private.apply_narrative_record_cutover(text,text,text,text,text,text,uuid,text,text)'::regprocedure
  ) INTO v_definition;
  v_required_locks:=ARRAY[
    'private.source_record','private.source_record_anchor_event',
    'private.source_record_occurrence','private.source_rendition',
    'private.source_record_placement','private.source_record_placement_decision',
    'private.source_persona','private.source_persona_placement',
    'private.source_persona_placement_decision',
    'private.source_persona_identity_event','private.source_persona_identity',
    'private.source_record_revision_event','public.person','public.source',
    'public.lineage_scheme_entry','public.haendelse'
  ];
  v_lock_tail:=substring(
    v_definition FROM strpos(v_definition,'LOCK TABLE private.source_record,')
  );
  v_lock_end:=strpos(v_lock_tail,'IN SHARE MODE;');
  IF v_lock_tail IS NULL OR v_lock_end=0 THEN
    RAISE EXCEPTION 'CUTOVER_CANONICAL_SOURCE_LOCK_CLAUSE_MISSING';
  END IF;
  SELECT array_agg(
           btrim(lock_name,E' \n\r\t') ORDER BY btrim(lock_name,E' \n\r\t')
         ) INTO v_actual_locks
    FROM unnest(string_to_array(
      substring(v_lock_tail FROM length('LOCK TABLE ')+1 FOR
        v_lock_end-length('LOCK TABLE ')-1),','
    )) AS lock_name;
  SELECT array_agg(lock_name ORDER BY lock_name) INTO v_required_locks
    FROM unnest(v_required_locks) AS lock_name;
  IF v_actual_locks IS DISTINCT FROM v_required_locks THEN
    RAISE EXCEPTION 'CUTOVER_CANONICAL_SOURCE_LOCK_SET_INVALID: %',v_actual_locks;
  END IF;
  RAISE NOTICE 'OK: cutover structural contract';
END
$cutover_structure$;

SAVEPOINT task7_behavior_scope;

DO $cutover_behavior$
DECLARE
  v_database jsonb;
  v_record_ref uuid := '70000000-0000-0000-0000-000000000710';
  v_run uuid := '70000000-0000-0000-0000-000000000711';
  v_binding uuid := '70000000-0000-0000-0000-000000000712';
  v_legacy_keep uuid := '70000000-0000-0000-0000-000000000713';
  v_legacy_hide uuid := '70000000-0000-0000-0000-000000000714';
  v_nonce uuid := '70000000-0000-0000-0000-000000000715';
  v_record_state jsonb;
  v_record_sha text;
  v_keep_state jsonb;
  v_keep_sha text;
  v_hide_state jsonb;
  v_hide_sha text;
  v_record_row jsonb;
  v_keep_row jsonb;
  v_hide_row jsonb;
  v_record_candidates text;
  v_legacy_candidates text;
  v_record_manifest text;
  v_legacy_manifest text;
  v_inventory text;
  v_inventory_drift text;
  v_approval text;
  v_approval_drift text;
  v_record_candidates_sha text;
  v_legacy_candidates_sha text;
  v_record_manifest_sha text;
  v_legacy_manifest_sha text;
  v_inventory_sha text;
  v_result jsonb;
  v_inserted bigint;
  v_error text;
  v_signature text;
BEGIN
  INSERT INTO public.source(id,slags,titel,udgave,aar)
  VALUES (-9700001,'DAA-udgave','Task 7 disposable','Task 7 disposable',1939);
  INSERT INTO private.extraction_run(
    id,source_id,run_key,schema_version,extractor_version,profile_version,
    input_sha256,manifest
  ) VALUES (
    v_run,-9700001,'task-7-disposable','1','test','test',repeat('7',64),'{}'
  );
  INSERT INTO private.source_record(
    id,public_ref,source_id,record_key,record_kind,created_run_id
  ) VALUES (
    v_record_ref,'70000000-0000-0000-0000-000000000716',-9700001,
    'task-7-record','person',v_run
  );
  INSERT INTO public.person(id,levende,privat,staged,visning_navn)
  VALUES
    (-9700001,false,false,false,'Task 7 bound'),
    (-9700002,false,false,false,'Task 7 keep'),
    (-9700003,false,false,false,'Task 7 hide'),
    (-9700004,false,false,false,'Task 7 unapproved dynamic row');
  INSERT INTO public.narrative(
    id,subjekt_type,subjekt_id,source_id,side,tekst,privat
  ) VALUES
    (1200000,'person',-9700001,-9700001,'1','Bound baseline',false),
    (1200001,'person',-9700002,-9700001,'2','Legacy keep',false),
    (1200002,'person',-9700003,-9700001,'3','Legacy hide',false);
  INSERT INTO private.narrative_record_publication(
    id,narrative_id,source_record_id,record_ref,record_label,citation_label,
    status,published_at
  ) VALUES (
    v_binding,1200000,v_record_ref,'70000000-0000-0000-0000-000000000717',
    'I.','Task 7, s. 1','published',clock_timestamp()
  );

  -- Three independent sequence floors: live row, deleted audit identity and an
  -- event payload identity; an already allocated sequence remains highest.
  INSERT INTO public.change_set(id,operation,summary)
  VALUES (-9700001,'task_7_history','Task 7 deleted historical narrative');
  INSERT INTO public.change_event(
    id,change_set_id,seq,tabel,row_pk,op,foer,efter
  ) VALUES (
    -9700001,-9700001,1,'narrative','{"id":1300000}','DELETE',
    '{"id":1300000,"tekst":"deleted"}','{"id":1350000,"tekst":"event referenced"}'
  );
  ALTER SEQUENCE public.narrative_id_seq RESTART WITH 1400000;

  v_database:=jsonb_build_object(
    'database_name',current_database(),
    'system_identifier',(pg_control_system()).system_identifier::text
  );
  v_record_state:=private.narrative_publication_state(
    -9700001,-9700001,'task-7-record'
  );
  v_record_sha:=encode(extensions.digest(v_record_state::text,'sha256'),'hex');
  v_keep_state:=private.narrative_legacy_candidate_publication_state(
    1200001,-9700001,v_legacy_keep
  );
  v_keep_sha:=encode(extensions.digest(v_keep_state::text,'sha256'),'hex');
  v_hide_state:=private.narrative_legacy_candidate_publication_state(
    1200002,-9700001,v_legacy_hide
  );
  v_hide_sha:=encode(extensions.digest(v_hide_state::text,'sha256'),'hex');
  v_record_row:=jsonb_build_object(
    'binding_id',v_binding::text,'narrative_id',1200000,'person_id',-9700001,
    'source_id',-9700001,'source_kind','DAA-udgave',
    'source_record_id',v_record_ref::text,'record_key','task-7-record',
    'status','published','record_label','I.','citation_label','Task 7, s. 1',
    'publication_state_sha256',v_record_sha,
    'narrative_text_sha256',encode(extensions.digest('Bound baseline','sha256'),'hex'),
    'binding_match_count',1,'row_sha256',repeat('1',64)
  );
  v_keep_row:=jsonb_build_object(
    'legacy_publication_ref',v_legacy_keep::text,'narrative_id',1200001,
    'person_id',-9700002,'source_id',-9700001,'source_kind','DAA-udgave',
    'narrative_text_sha256',encode(extensions.digest('Legacy keep','sha256'),'hex'),
    'baseline_sha256',v_keep_sha,'binding_match_count',0,'row_sha256',repeat('2',64)
  );
  v_hide_row:=jsonb_build_object(
    'legacy_publication_ref',v_legacy_hide::text,'narrative_id',1200002,
    'person_id',-9700003,'source_id',-9700001,'source_kind','DAA-udgave',
    'narrative_text_sha256',encode(extensions.digest('Legacy hide','sha256'),'hex'),
    'baseline_sha256',v_hide_sha,'binding_match_count',0,'row_sha256',repeat('3',64)
  );
  v_record_candidates:=jsonb_build_object(
    'schema_version','narrative-record-baseline-candidates-v1',
    'database',v_database,'rows',jsonb_build_array(v_record_row)
  )::text;
  v_legacy_candidates:=jsonb_build_object(
    'schema_version','narrative-legacy-baseline-candidates-v1',
    'database',v_database,'rows',jsonb_build_array(v_keep_row,v_hide_row)
  )::text;
  v_inventory:=jsonb_build_object(
    'schema_version','narrative-record-cutover-inventory-v1','database',v_database,
    'record_candidate_ids',jsonb_build_array(v_binding::text),
    'legacy_candidate_ids',jsonb_build_array(1200001,1200002),
    'counts_by_source',jsonb_build_array(jsonb_build_object(
      'source_id',-9700001,'record_candidates',1,'legacy_candidates',2)),
    'accepted_identity_count',0,'identity_blocked_record_count',1,
    'classified_direct_readers',jsonb_build_array(
      jsonb_build_object('path','mobile/src/data/about.ts','classification','non_person_control'),
      jsonb_build_object('path','mobile/src/data/haendelser.ts','classification','rls_gated_metadata'),
      jsonb_build_object('path','mobile/src/data/load.ts','classification','v2_public_rpc'),
      jsonb_build_object('path','mobile/src/data/presensLinjer.ts','classification','non_person_control'),
      jsonb_build_object('path','mobile/src/data/publicBioVersions.ts','classification','v2_public_rpc'),
      jsonb_build_object('path','mobile/src/data/redaktionRead.ts','classification','v2_editor_rpc'),
      jsonb_build_object('path','web/src/data/feedAux.ts','classification','v2_public_rpc'),
      jsonb_build_object('path','web/src/data/haendelser.ts','classification','rls_gated_metadata'),
      jsonb_build_object('path','web/src/data/presensLinjer.ts','classification','non_person_control'),
      jsonb_build_object('path','web/src/data/public.ts','classification','v2_public_rpc'),
      jsonb_build_object('path','web/src/data/redaktionRead.ts','classification','v2_editor_rpc')
    )
  )::text;
  v_record_candidates_sha:=encode(extensions.digest(
    convert_to(v_record_candidates,'UTF8'),'sha256'),'hex');
  v_legacy_candidates_sha:=encode(extensions.digest(
    convert_to(v_legacy_candidates,'UTF8'),'sha256'),'hex');
  v_inventory_sha:=encode(extensions.digest(
    convert_to(v_inventory,'UTF8'),'sha256'),'hex');
  v_record_manifest:=jsonb_build_object(
    'schema_version','narrative-record-baseline-manifest-v1','database',v_database,
    'record_candidates_sha256',v_record_candidates_sha,
    'rows',jsonb_build_array(v_record_row)
  )::text;
  v_legacy_manifest:=jsonb_build_object(
    'schema_version','narrative-legacy-baseline-manifest-v1','database',v_database,
    'legacy_candidates_sha256',v_legacy_candidates_sha,
    'rows',jsonb_build_array(v_keep_row)
  )::text;
  v_record_manifest_sha:=encode(extensions.digest(
    convert_to(v_record_manifest,'UTF8'),'sha256'),'hex');
  v_legacy_manifest_sha:=encode(extensions.digest(
    convert_to(v_legacy_manifest,'UTF8'),'sha256'),'hex');
  v_approval:=jsonb_build_object(
    'schema_version','narrative-record-cutover-approval-v1','database',v_database,
    'input_hashes',jsonb_build_object(
      'approval_decisions_sha256',repeat('a',64),
      'record_candidates_sha256',v_record_candidates_sha,
      'legacy_candidates_sha256',v_legacy_candidates_sha,
      'record_manifest_sha256',v_record_manifest_sha,
      'legacy_manifest_sha256',v_legacy_manifest_sha,
      'inventory_sha256',v_inventory_sha),
    'record_approved_ids',jsonb_build_array(v_binding::text),
    'record_approved_rows',jsonb_build_array(jsonb_build_object(
      'binding_id',v_binding::text,'row_sha256',repeat('1',64))),
    'legacy_keep_ids',jsonb_build_array(1200001),
    'legacy_keep_rows',jsonb_build_array(jsonb_build_object(
      'narrative_id',1200001,'legacy_publication_ref',v_legacy_keep::text,
      'row_sha256',repeat('2',64))),
    'legacy_hide_ids',jsonb_build_array(1200002),
    'legacy_hide_rows',jsonb_build_array(jsonb_build_object(
      'narrative_id',1200002,'row_sha256',repeat('3',64))),
    'counts',jsonb_build_object(
      'record_approved',1,'legacy_candidates',2,'legacy_keep',1,'legacy_hide',1)
  )::text;

  -- One-byte drift aborts before any cutover write.
  v_error:=NULL;
  BEGIN
    PERFORM private.apply_narrative_record_cutover(
      v_record_candidates,v_legacy_candidates,v_record_manifest,v_legacy_manifest,
      v_inventory||' ',v_approval,v_nonce,current_database(),
      (pg_control_system()).system_identifier::text
    );
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS DISTINCT FROM 'CUTOVER_ARTIFACT_HASH_MISMATCH'
     OR EXISTS (SELECT 1 FROM private.narrative_record_cutover_receipt) THEN
    RAISE EXCEPTION 'CUTOVER_DRIFT_DID_NOT_FAIL_CLOSED: %',v_error;
  END IF;

  -- Inventory consequence metrics are live gates, not merely reviewed prose.
  v_inventory_drift:=jsonb_set(
    v_inventory::jsonb,'{accepted_identity_count}','1'::jsonb
  )::text;
  v_approval_drift:=jsonb_set(
    v_approval::jsonb,'{input_hashes,inventory_sha256}',to_jsonb(encode(
      extensions.digest(convert_to(v_inventory_drift,'UTF8'),'sha256'),'hex'
    ))
  )::text;
  v_error:=NULL;
  BEGIN
    PERFORM private.apply_narrative_record_cutover(
      v_record_candidates,v_legacy_candidates,v_record_manifest,v_legacy_manifest,
      v_inventory_drift,v_approval_drift,v_nonce,current_database(),
      (pg_control_system()).system_identifier::text
    );
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS DISTINCT FROM 'CUTOVER_INVENTORY_LIVE_DRIFT'
     OR EXISTS (SELECT 1 FROM private.narrative_record_cutover_receipt) THEN
    RAISE EXCEPTION 'CUTOVER_INVENTORY_DRIFT_DID_NOT_FAIL_CLOSED: %',v_error;
  END IF;

  -- A live row created after approval is not inferred or inserted dynamically.
  INSERT INTO public.narrative(
    id,subjekt_type,subjekt_id,source_id,side,tekst,privat
  ) VALUES (
    1200003,'person',-9700004,-9700001,'4','Unapproved dynamic row',false
  );
  v_error:=NULL;
  BEGIN
    PERFORM private.apply_narrative_record_cutover(
      v_record_candidates,v_legacy_candidates,v_record_manifest,v_legacy_manifest,
      v_inventory,v_approval,v_nonce,current_database(),
      (pg_control_system()).system_identifier::text
    );
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS DISTINCT FROM 'CUTOVER_LEGACY_LIVE_SET_DRIFT'
     OR EXISTS (SELECT 1 FROM private.narrative_record_cutover_receipt
                 WHERE nonce=v_nonce)
     OR EXISTS (SELECT 1 FROM public.change_set
                 WHERE operation='narrative_record_contract_cutover') THEN
    RAISE EXCEPTION 'CUTOVER_DYNAMIC_ROW_DID_NOT_FAIL_CLOSED: %',v_error;
  END IF;
  DELETE FROM public.narrative WHERE id=1200003;

  -- An approved record whose semantic live baseline drifts also fails before
  -- the change-set, events, receipt, ACL or version can be mutated.
  UPDATE public.narrative SET tekst='Bound baseline drift' WHERE id=1200000;
  v_error:=NULL;
  BEGIN
    PERFORM private.apply_narrative_record_cutover(
      v_record_candidates,v_legacy_candidates,v_record_manifest,v_legacy_manifest,
      v_inventory,v_approval,v_nonce,current_database(),
      (pg_control_system()).system_identifier::text
    );
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS DISTINCT FROM 'CUTOVER_RECORD_LIVE_SET_DRIFT'
     OR EXISTS (SELECT 1 FROM private.narrative_record_cutover_receipt
                 WHERE nonce=v_nonce)
     OR public.narrative_record_contract_version()<>1 THEN
    RAISE EXCEPTION 'CUTOVER_RECORD_DRIFT_DID_NOT_FAIL_CLOSED: %',v_error;
  END IF;
  UPDATE public.narrative SET tekst='Bound baseline' WHERE id=1200000;

  v_result:=private.apply_narrative_record_cutover(
    v_record_candidates,v_legacy_candidates,v_record_manifest,v_legacy_manifest,
    v_inventory,v_approval,v_nonce,current_database(),
    (pg_control_system()).system_identifier::text
  );
  IF public.narrative_record_contract_version()<>2
     OR jsonb_array_length(v_result->'record_events')<>1
     OR jsonb_array_length(v_result->'legacy_events')<>1
     OR v_result #>> '{legacy_hidden_ids,0}' IS DISTINCT FROM '1200002'
     OR (v_result #>> '{sequence,before}')::bigint<>1400000
     OR (v_result #>> '{sequence,floor}')::bigint<>1400001
     OR (v_result #>> '{sequence,after}')::bigint<>1400001 THEN
    RAISE EXCEPTION 'CUTOVER_RESULT_INVALID: %',v_result;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM private.narrative_legacy_publication
                  WHERE narrative_id=1200001 AND status='grandfathered_publication')
     OR EXISTS (SELECT 1 FROM private.narrative_legacy_publication
                WHERE narrative_id=1200002)
     OR (SELECT count(*) FROM private.narrative_publication_event
          WHERE event_type='baseline')<>2
     OR (SELECT count(*) FROM private.narrative_record_cutover_receipt
          WHERE nonce=v_nonce)<>1 THEN
    RAISE EXCEPTION 'CUTOVER_WRITE_SET_INVALID';
  END IF;
  INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,tekst,privat)
  VALUES ('line',-9700999,NULL,'Sequence proof',false)
  RETURNING id INTO v_inserted;
  IF v_inserted<>1400001 THEN
    RAISE EXCEPTION 'CUTOVER_SEQUENCE_NEXT_DEFAULT_INVALID: %',v_inserted;
  END IF;

  FOREACH v_signature IN ARRAY ARRAY[
    'public.red_upsert_person_narrative_record(bigint,bigint,text,text,boolean,text)',
    'public.red_publicer_person_narrative_record(bigint,bigint,text,text)',
    'public.red_revider_publiceret_person_narrative_record(bigint,bigint,text,text,text)',
    'public.red_revalider_person_narrative_record(bigint,bigint,text,text)',
    'public.red_kasser_person_narrative_record(bigint,bigint,text,text)',
    'public.red_tilbagetraek_person_narrative_record(bigint,bigint,text,text)',
    'public.red_tilbagetraek_legacy_narrative(uuid,text,text)',
    'public.red_fortryd_person_narrative_publication_event(uuid,text)',
    'public.red_begin_1939_v50_reimport(uuid,text,text)',
    'public.red_apply_1939_v50_source_evidence(uuid,text,jsonb)',
    'public.red_apply_1939_v50_person_create(uuid,text,jsonb)',
    'public.red_apply_1939_v50_canonical_delta(uuid,text,jsonb)',
    'public.red_finalize_1939_v50_reimport(uuid)',
    'public.red_reverse_1939_v50_reimport(uuid,uuid)',
    'public.red_activate_1939_v50_batch(uuid,uuid)',
    'public.red_lock_1939_v50_name_completion(text)',
    'public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb)',
    'public.red_begin_1939_v50_name_completion(uuid,text,uuid)',
    'public.red_apply_1939_v50_name_completion(uuid,text,jsonb)',
    'public.red_finalize_1939_v50_name_completion(uuid)'
  ] LOOP
    IF NOT has_function_privilege('authenticated',v_signature,'EXECUTE')
       OR has_function_privilege('service_role',v_signature,'EXECUTE') THEN
      RAISE EXCEPTION 'CUTOVER_NEW_WRITER_ACL_INVALID: %',v_signature;
    END IF;
  END LOOP;
  FOREACH v_signature IN ARRAY ARRAY[
    'public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamptz)',
    'public.red_authorize_1939_v50_reversal(uuid,uuid,timestamptz)',
    'public.red_authorize_1939_v50_cutover(uuid,uuid,timestamptz)',
    'public.red_authorize_1939_v50_name_completion(text,uuid,text,text,jsonb,jsonb)'
  ] LOOP
    IF NOT has_function_privilege('service_role',v_signature,'EXECUTE')
       OR has_function_privilege('authenticated',v_signature,'EXECUTE') THEN
      RAISE EXCEPTION 'CUTOVER_1939_FACADE_SERVICE_ACL_INVALID: %',v_signature;
    END IF;
  END LOOP;
  FOREACH v_signature IN ARRAY ARRAY[
    'public.red_publicer_narrative_record(bigint,uuid,text,text)',
    'public.red_tilbagetraek_narrative_record(bigint)',
    'public.red_apply_reimport_cases(uuid,text,text)',
    'public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)'
  ] LOOP
    IF has_function_privilege('authenticated',v_signature,'EXECUTE')
       OR has_function_privilege('service_role',v_signature,'EXECUTE') THEN
      RAISE EXCEPTION 'CUTOVER_LEGACY_WRITER_ACL_LEAK: %',v_signature;
    END IF;
  END LOOP;

  v_error:=NULL;
  BEGIN
    UPDATE private.narrative_record_cutover_receipt SET database_name='drift'
     WHERE nonce=v_nonce;
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS DISTINCT FROM 'NARRATIVE_RECORD_CUTOVER_RECEIPT_APPEND_ONLY' THEN
    RAISE EXCEPTION 'CUTOVER_RECEIPT_UPDATE_NOT_REJECTED: %',v_error;
  END IF;
  v_error:=NULL;
  BEGIN
    PERFORM private.apply_narrative_record_cutover(
      v_record_candidates,v_legacy_candidates,v_record_manifest,v_legacy_manifest,
      v_inventory,v_approval,v_nonce,current_database(),
      (pg_control_system()).system_identifier::text
    );
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS DISTINCT FROM 'CUTOVER_CONTRACT_VERSION_NOT_ONE' THEN
    RAISE EXCEPTION 'CUTOVER_RERUN_NOT_REJECTED: %',v_error;
  END IF;
  RAISE NOTICE 'OK: exact atomic cutover, ACL, receipt and monotone sequence';
END
$cutover_behavior$;

ROLLBACK TO SAVEPOINT task7_behavior_scope;
RELEASE SAVEPOINT task7_behavior_scope;

-- The cutover's ACL rewrite and version-last update must be invisible as a
-- mixed state. A separate read-committed client observes v1 before commit and
-- exact v2 ACL only after commit; the disposable fixture is then atomically
-- restored to v1 for the remaining compatibility test.
DO $cutover_visibility_connect$
BEGIN
  PERFORM extensions.dblink_connect(
    'task7_cutover_observer',
    format(
      'dbname=%s host=127.0.0.1 port=%s user=%s password=',
      current_database(),current_setting('port'),current_user
    )
  );
END
$cutover_visibility_connect$;

DO $cutover_visibility_stage$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-narrative-record-contract',0));
  LOCK TABLE private.narrative_record_contract IN SHARE ROW EXCLUSIVE MODE;
  PERFORM private.apply_narrative_record_contract_acl(2);
  UPDATE private.narrative_record_contract
     SET version=2,changed_at=clock_timestamp()
   WHERE singleton AND version=1;
  IF NOT FOUND THEN RAISE EXCEPTION 'CUTOVER_VISIBILITY_STAGE_VERSION_FAILED'; END IF;
END
$cutover_visibility_stage$;

DO $cutover_visibility_before_commit$
DECLARE
  v_version integer;
  v_new_authenticated boolean;
  v_new_service boolean;
  v_legacy_authenticated boolean;
BEGIN
  SELECT version,new_authenticated,new_service,legacy_authenticated
    INTO v_version,v_new_authenticated,v_new_service,v_legacy_authenticated
    FROM extensions.dblink(
      'task7_cutover_observer',
      $observer_sql$
        SELECT public.narrative_record_contract_version(),
          has_function_privilege(
            'authenticated',
            'public.red_upsert_person_narrative_record(bigint,bigint,text,text,boolean,text)',
            'EXECUTE'
          ),
          has_function_privilege(
            'service_role',
            'public.red_upsert_person_narrative_record(bigint,bigint,text,text,boolean,text)',
            'EXECUTE'
          ),
          has_function_privilege(
            'authenticated',
            'public.red_publicer_narrative_record(bigint,uuid,text,text)',
            'EXECUTE'
          )
      $observer_sql$
    ) AS observed(
      version integer,new_authenticated boolean,new_service boolean,
      legacy_authenticated boolean
    );
  IF v_version<>1 OR v_new_authenticated OR v_new_service OR NOT v_legacy_authenticated THEN
    RAISE EXCEPTION 'CUTOVER_UNCOMMITTED_STATE_VISIBLE: %,%,%,%',
      v_version,v_new_authenticated,v_new_service,v_legacy_authenticated;
  END IF;
END
$cutover_visibility_before_commit$;

COMMIT;

DO $cutover_visibility_after_commit$
DECLARE
  v_version integer;
  v_new_authenticated boolean;
  v_new_service boolean;
  v_legacy_authenticated boolean;
BEGIN
  SELECT version,new_authenticated,new_service,legacy_authenticated
    INTO v_version,v_new_authenticated,v_new_service,v_legacy_authenticated
    FROM extensions.dblink(
      'task7_cutover_observer',
      $observer_sql$
        SELECT public.narrative_record_contract_version(),
          has_function_privilege(
            'authenticated',
            'public.red_upsert_person_narrative_record(bigint,bigint,text,text,boolean,text)',
            'EXECUTE'
          ),
          has_function_privilege(
            'service_role',
            'public.red_upsert_person_narrative_record(bigint,bigint,text,text,boolean,text)',
            'EXECUTE'
          ),
          has_function_privilege(
            'authenticated',
            'public.red_publicer_narrative_record(bigint,uuid,text,text)',
            'EXECUTE'
          )
      $observer_sql$
    ) AS observed(
      version integer,new_authenticated boolean,new_service boolean,
      legacy_authenticated boolean
    );
  IF v_version<>2 OR NOT v_new_authenticated OR v_new_service OR v_legacy_authenticated THEN
    RAISE EXCEPTION 'CUTOVER_COMMITTED_STATE_INVALID: %,%,%,%',
      v_version,v_new_authenticated,v_new_service,v_legacy_authenticated;
  END IF;
  RAISE NOTICE 'OK: separate client sees v1 ACL before commit and exact v2 ACL after commit';
END
$cutover_visibility_after_commit$;

BEGIN;
DO $cutover_visibility_restore$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('daa-narrative-record-contract',0));
  LOCK TABLE private.narrative_record_contract IN SHARE ROW EXCLUSIVE MODE;
  PERFORM private.apply_narrative_record_contract_acl(1);
  UPDATE private.narrative_record_contract
     SET version=1,changed_at=clock_timestamp()
   WHERE singleton AND version=2;
  IF NOT FOUND THEN RAISE EXCEPTION 'CUTOVER_VISIBILITY_RESTORE_VERSION_FAILED'; END IF;
END
$cutover_visibility_restore$;
COMMIT;

DO $cutover_visibility_disconnect$
BEGIN
  PERFORM extensions.dblink_disconnect('task7_cutover_observer');
END
$cutover_visibility_disconnect$;

BEGIN;
DO $cutover_source_truth_concurrency$
DECLARE
  v_connection text:=format(
    'dbname=%s host=127.0.0.1 port=%s user=%s password=',
    current_database(),current_setting('port'),current_user
  );
  v_cutover_connected boolean:=false;
  v_writer_connected boolean:=false;
  v_cutover_pid integer;
  v_writer_pid integer;
  v_busy integer;
  v_result text;
  v_deadline timestamptz;
  v_case integer;
  v_writer_sql text;
  v_writer_label text;
BEGIN
  PERFORM extensions.dblink_connect('task7_source_cutover',v_connection);
  v_cutover_connected:=true;
  PERFORM extensions.dblink_connect('task7_source_writer',v_connection);
  v_writer_connected:=true;
  SELECT pid INTO v_cutover_pid
    FROM extensions.dblink('task7_source_cutover','SELECT pg_backend_pid()') AS t(pid integer);
  SELECT pid INTO v_writer_pid
    FROM extensions.dblink('task7_source_writer','SELECT pg_backend_pid()') AS t(pid integer);
  FOR v_case IN 1..2 LOOP
    IF v_case=1 THEN
      v_writer_label:='persona-placement-decision';
      v_writer_sql:='WITH changed AS (UPDATE private.source_persona_placement_decision '
        ||'SET version=version WHERE false RETURNING 1) '
        ||'SELECT count(*)::text FROM changed';
    ELSE
      v_writer_label:='persona-identity';
      v_writer_sql:='WITH changed AS (UPDATE private.source_persona_identity '
        ||'SET updated_at=updated_at WHERE false RETURNING 1) '
        ||'SELECT count(*)::text FROM changed';
    END IF;
    PERFORM extensions.dblink_exec('task7_source_cutover','BEGIN');
    PERFORM extensions.dblink_exec(
      'task7_source_cutover',
      'LOCK TABLE private.source_record_placement, private.source_persona_placement_decision, '
      ||'private.source_persona_identity IN SHARE MODE'
    );
    PERFORM extensions.dblink_send_query('task7_source_writer',v_writer_sql);
    v_deadline:=clock_timestamp()+interval '3 seconds';
    LOOP
      EXIT WHEN v_cutover_pid=ANY(pg_blocking_pids(v_writer_pid));
      SELECT extensions.dblink_is_busy('task7_source_writer') INTO v_busy;
      IF v_busy=0 THEN
        RAISE EXCEPTION 'CUTOVER_SOURCE_WRITER_DID_NOT_BLOCK: %',v_writer_label;
      END IF;
      IF clock_timestamp()>v_deadline THEN
        RAISE EXCEPTION 'CUTOVER_SOURCE_WRITER_BLOCK_TIMEOUT: %',v_writer_label;
      END IF;
      PERFORM pg_sleep(0.02);
    END LOOP;
    PERFORM extensions.dblink_exec('task7_source_cutover','COMMIT');
    v_deadline:=clock_timestamp()+interval '3 seconds';
    LOOP
      SELECT extensions.dblink_is_busy('task7_source_writer') INTO v_busy;
      EXIT WHEN v_busy=0;
      IF clock_timestamp()>v_deadline THEN
        RAISE EXCEPTION 'CUTOVER_SOURCE_WRITER_RESUME_TIMEOUT: %',v_writer_label;
      END IF;
      PERFORM pg_sleep(0.02);
    END LOOP;
    SELECT result INTO v_result
      FROM extensions.dblink_get_result('task7_source_writer') AS t(result text);
    PERFORM result FROM extensions.dblink_get_result('task7_source_writer') AS t(result text);
    IF v_result IS DISTINCT FROM '0' THEN
      RAISE EXCEPTION 'CUTOVER_SOURCE_WRITER_RESULT_INVALID: %, %',v_writer_label,v_result;
    END IF;
  END LOOP;
  PERFORM extensions.dblink_disconnect('task7_source_writer'); v_writer_connected:=false;
  PERFORM extensions.dblink_disconnect('task7_source_cutover'); v_cutover_connected:=false;
  RAISE NOTICE 'OK: canonical persona-placement decision and identity writers serialize behind cutover source locks';
EXCEPTION WHEN OTHERS THEN
  IF v_writer_connected THEN
    BEGIN PERFORM extensions.dblink_cancel_query('task7_source_writer'); EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM extensions.dblink_disconnect('task7_source_writer'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  IF v_cutover_connected THEN
    BEGIN PERFORM extensions.dblink_exec('task7_source_cutover','ROLLBACK'); EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM extensions.dblink_disconnect('task7_source_cutover'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  RAISE;
END
$cutover_source_truth_concurrency$;

ROLLBACK;
