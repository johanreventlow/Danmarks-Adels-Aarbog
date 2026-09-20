\set ON_ERROR_STOP on

-- A pre-#153 ledger whose only reimport batch created no person: it wrote
-- source evidence, was finalized, and then had nowhere left to go.  The v1
-- cutover RPC requires exactly one complete name-completion child, and a
-- child can only exist for an authorized person_create, so `finalized` *is*
-- this batch's terminal state.  Production carries exactly one such batch
-- (1939 fase A, 584 source_evidence / 0 person_creates), so the #153 upgrade
-- must migrate it instead of rejecting the whole ledger as in-flight.
--
-- The rows are inserted directly, in a named disposable database only, the
-- same way reimport-writer-legacy-invalid-terminal-fixture.sql does: the
-- historic public source-evidence RPC needs a full extraction-run/rendition
-- setup that this migration assertion does not exercise.  The marker record
-- keys keep the post-migration assertion independent of generated ids.

DO $fixture$
DECLARE
  v_batch uuid := '15300000-0000-4000-8000-000000000301';
  v_authorization uuid := '15300000-0000-4000-8000-000000000302';
  v_principal uuid := '15300000-0000-4000-8000-000000000303';
  v_nonce uuid := '15300000-0000-4000-8000-000000000304';
  v_expected_counts jsonb := '{"person_creates":0,"source_evidence":3,"canonical_delta":0}';
  v_elements jsonb := '{}'::jsonb;
  v_index int;
BEGIN
  INSERT INTO public.source(id,titel,udgave,slags)
  VALUES(3,'DAA','1939','DAA-udgave') ON CONFLICT(id) DO NOTHING;

  FOR v_index IN 1..3 LOOP
    v_elements := v_elements || jsonb_build_object(
      'source-evidence:legacy-source-evidence-153-'||v_index,
      jsonb_build_object('source_record_key','legacy-source-evidence-153-'||v_index)
    );
  END LOOP;

  INSERT INTO private.reimport_1939_authorization(
    id,operation,manifest_sha256,preview_sha256,database_identity,source_id,
    expected_counts,authorized_elements,principal_id,nonce,expires_at,status,consumed_at
  ) VALUES(
    v_authorization,'reimport',repeat('3',64),repeat('4',64),current_database(),3,
    v_expected_counts,v_elements,v_principal,v_nonce,
    clock_timestamp()+interval '1 hour','consumed',clock_timestamp()
  );
  INSERT INTO private.reimport_1939_write_batch(
    id,authorization_id,manifest_sha256,preview_sha256,principal_id,status,
    expected_counts,observed_counts,finalized_at
  ) VALUES(
    v_batch,v_authorization,repeat('3',64),repeat('4',64),v_principal,'finalized',
    v_expected_counts,v_expected_counts,clock_timestamp()
  );
  FOR v_index IN 1..3 LOOP
    INSERT INTO private.reimport_1939_write_event(
      batch_id,element_id,operation,source_record_key,payload,after_sha256
    ) VALUES(
      v_batch,'source-evidence:legacy-source-evidence-153-'||v_index,'source_evidence',
      'legacy-source-evidence-153-'||v_index,
      jsonb_build_object('source_record_key','legacy-source-evidence-153-'||v_index),
      repeat('5',64)
    );
  END LOOP;
END $fixture$;
