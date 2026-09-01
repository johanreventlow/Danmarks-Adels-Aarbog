\set ON_ERROR_STOP on

-- Local, disposable #152 fixture. The artifacts are constructed in the same
-- canonical shapes and passed through the real atomic cutover kernel.
DO $v2fixture$
DECLARE
  v_actor uuid := '15300000-0000-4000-8000-000000000001';
  v_record uuid := '15300000-0000-4000-8000-000000000002';
  v_run uuid := '15300000-0000-4000-8000-000000000003';
  v_nonce uuid := '15300000-0000-4000-8000-000000000004';
  v_database jsonb; v_records text; v_legacy text; v_record_manifest text; v_legacy_manifest text; v_inventory text; v_approval text; v_result jsonb;
  v_records_sha text; v_legacy_sha text; v_record_manifest_sha text; v_legacy_manifest_sha text; v_inventory_sha text;
BEGIN
  IF public.narrative_record_contract_version()=2 THEN RETURN; END IF;
  IF public.narrative_record_contract_version()<>1 THEN RAISE EXCEPTION 'REIMPORT_WRITER_V2_BOOTSTRAP_UNEXPECTED_CONTRACT_VERSION'; END IF;
  INSERT INTO auth.users(id,email) VALUES(v_actor,'reimport-writer-v2-fixture@example.invalid') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.profiles(id,email,rolle,navn) VALUES(v_actor,'reimport-writer-v2-fixture@example.invalid','redaktion','Reimport writer v2 fixture') ON CONFLICT(id) DO UPDATE SET rolle='redaktion',navn='Reimport writer v2 fixture';
  INSERT INTO public.source(id,slags,titel,udgave,aar) VALUES(-153001,'DAA-udgave','Reimport writer v2 fixture','Synthetic',1939) ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) VALUES(v_run,-153001,'reimport-writer-v2-bootstrap','fixture','fixture','fixture',repeat('1',64),'{}') ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.source_record(id,public_ref,source_id,record_key,record_kind,created_run_id) VALUES(v_record,'15300000-0000-4000-8000-000000000005',-153001,'reimport-writer-v2-bootstrap','person',v_run) ON CONFLICT(id) DO NOTHING;
  v_database:=jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text);
  v_records:=jsonb_build_object('schema_version','narrative-record-baseline-candidates-v1','database',v_database,'rows','[]'::jsonb)::text;
  v_legacy:=jsonb_build_object('schema_version','narrative-legacy-baseline-candidates-v1','database',v_database,'rows','[]'::jsonb)::text;
  v_records_sha:=encode(extensions.digest(convert_to(v_records,'UTF8'),'sha256'),'hex'); v_legacy_sha:=encode(extensions.digest(convert_to(v_legacy,'UTF8'),'sha256'),'hex');
  v_inventory:=jsonb_build_object('schema_version','narrative-record-cutover-inventory-v1','database',v_database,'record_candidate_ids','[]'::jsonb,'legacy_candidate_ids','[]'::jsonb,'counts_by_source','[]'::jsonb,'accepted_identity_count',0,'identity_blocked_record_count',1,'classified_direct_readers',jsonb_build_array(jsonb_build_object('path','mobile/src/data/about.ts','classification','non_person_control'),jsonb_build_object('path','mobile/src/data/haendelser.ts','classification','rls_gated_metadata'),jsonb_build_object('path','mobile/src/data/load.ts','classification','v2_public_rpc'),jsonb_build_object('path','mobile/src/data/presensLinjer.ts','classification','non_person_control'),jsonb_build_object('path','mobile/src/data/publicBioVersions.ts','classification','v2_public_rpc'),jsonb_build_object('path','mobile/src/data/redaktionRead.ts','classification','v2_editor_rpc'),jsonb_build_object('path','web/src/data/feedAux.ts','classification','v2_public_rpc'),jsonb_build_object('path','web/src/data/haendelser.ts','classification','rls_gated_metadata'),jsonb_build_object('path','web/src/data/presensLinjer.ts','classification','non_person_control'),jsonb_build_object('path','web/src/data/public.ts','classification','v2_public_rpc'),jsonb_build_object('path','web/src/data/redaktionRead.ts','classification','v2_editor_rpc'))))::text;
  v_inventory_sha:=encode(extensions.digest(convert_to(v_inventory,'UTF8'),'sha256'),'hex');
  v_record_manifest:=jsonb_build_object('schema_version','narrative-record-baseline-manifest-v1','database',v_database,'record_candidates_sha256',v_records_sha,'rows','[]'::jsonb)::text;
  v_legacy_manifest:=jsonb_build_object('schema_version','narrative-legacy-baseline-manifest-v1','database',v_database,'legacy_candidates_sha256',v_legacy_sha,'rows','[]'::jsonb)::text;
  v_record_manifest_sha:=encode(extensions.digest(convert_to(v_record_manifest,'UTF8'),'sha256'),'hex'); v_legacy_manifest_sha:=encode(extensions.digest(convert_to(v_legacy_manifest,'UTF8'),'sha256'),'hex');
  v_approval:=jsonb_build_object(
    'schema_version','narrative-record-cutover-approval-v1','database',v_database,
    'input_hashes',jsonb_build_object('approval_decisions_sha256',repeat('a',64),'record_candidates_sha256',v_records_sha,'legacy_candidates_sha256',v_legacy_sha,'record_manifest_sha256',v_record_manifest_sha,'legacy_manifest_sha256',v_legacy_manifest_sha,'inventory_sha256',v_inventory_sha),
    'record_approved_ids','[]'::jsonb,'record_approved_rows','[]'::jsonb,
    'legacy_keep_ids','[]'::jsonb,'legacy_keep_rows','[]'::jsonb,
    'legacy_hide_ids','[]'::jsonb,'legacy_hide_rows','[]'::jsonb,
    'counts',jsonb_build_object('record_approved',0,'legacy_candidates',0,'legacy_keep',0,'legacy_hide',0)
  )::text;
  v_result:=private.apply_narrative_record_cutover(v_records,v_legacy,v_record_manifest,v_legacy_manifest,v_inventory,v_approval,v_nonce,current_database(),(pg_control_system()).system_identifier::text);
  IF public.narrative_record_contract_version()<>2 THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_V2_BOOTSTRAP_CUTOVER_FAILED';
  END IF;
END $v2fixture$;
