\set ON_ERROR_STOP on

-- Deliberately malformed pre-#153 ledgers.  They are inserted only in named
-- disposable databases to prove the upgrade rejects terminal-looking rows
-- that the historic public RPC lifecycle could not have produced.
\if :{?terminal_negative_case}
\else
\quit
\endif

SELECT set_config('app.reimport_writer_invalid_terminal_case', :'terminal_negative_case', false);

DO $fixture$
DECLARE
  v_case text := current_setting('app.reimport_writer_invalid_terminal_case');
  v_source_id uuid := '15300000-0000-4000-8000-000000000201';
  v_child_id uuid := '15300000-0000-4000-8000-000000000202';
  v_source_authorization uuid := '15300000-0000-4000-8000-000000000203';
  v_child_authorization uuid := '15300000-0000-4000-8000-000000000204';
  v_terminal_authorization uuid := '15300000-0000-4000-8000-000000000205';
  v_payload jsonb;
  v_payloads jsonb;
  v_source_payload jsonb;
  v_result_sha256 text;
  v_ledger_source_id bigint := CASE WHEN v_case='identity_wrong_source' THEN 4 ELSE 3 END;
BEGIN
  IF v_case NOT IN ('orphan','reversed_finalized_child','broken_result','ambiguous_child',
                    'identity_wrong_source','identity_multi_source') THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_INVALID_TERMINAL_FIXTURE_CASE_UNKNOWN';
  END IF;
  INSERT INTO public.source(id,titel,udgave,slags)
  VALUES(3,'DAA','1939','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  IF v_case IN ('identity_wrong_source','identity_multi_source') THEN
    INSERT INTO public.source(id,titel,udgave,slags)
    VALUES(4,'Other','1939','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  END IF;

  IF v_case='orphan' THEN
    INSERT INTO private.reimport_1939_authorization(
      id,operation,manifest_sha256,preview_sha256,database_identity,source_id,
      expected_counts,authorized_elements,principal_id,nonce,expires_at,status,consumed_at
    ) VALUES(
      v_child_authorization,'name_completion',repeat('c',64),repeat('d',64),
      current_database(),3,'{"name_completions":1,"operations":1}',
      jsonb_build_object('payloads',jsonb_build_object(
        'name-completion:orphan',jsonb_build_object('source_batch_id','15300000-0000-4000-8000-000000000299')
      )),
      '15300000-0000-4000-8000-000000000206','15300000-0000-4000-8000-000000000207',
      clock_timestamp()+interval '1 hour','consumed',clock_timestamp()
    );
    INSERT INTO private.reimport_1939_write_batch(
      id,authorization_id,manifest_sha256,preview_sha256,principal_id,status,expected_counts,observed_counts,finalized_at
    ) VALUES(
      v_child_id,v_child_authorization,repeat('c',64),repeat('d',64),
      '15300000-0000-4000-8000-000000000206','finalized',
      '{"name_completions":1,"operations":1}','{"name_completions":1,"operations":1}',clock_timestamp()
    );
    RETURN;
  END IF;

  v_source_payload := jsonb_build_object(
    'source_record_key','legacy-invalid-terminal',
    'source_persona_id','15300000-0000-4000-8000-000000000208',
    'name','Invalid terminal fixture'
  );
  v_payload := jsonb_build_object(
    'source_batch_id',v_source_id,
    'source_person_create_element_id','person-create:legacy-invalid-terminal',
    'person_id',153201,
    'source_record_key','legacy-invalid-terminal',
    'source_persona_id','15300000-0000-4000-8000-000000000208',
    'source_payload_sha256',private.reimport_1939_canonical_json_sha256(v_source_payload)
  );
  v_payloads := jsonb_build_object('name-completion:legacy-invalid-terminal',v_payload);
  v_result_sha256 := private.reimport_1939_canonical_json_sha256(jsonb_build_object(
    'fact_id',153202,'assertion_id',153203,'citation_id',153204,'conclusion_id',153205
  ));

  INSERT INTO private.reimport_1939_authorization(
    id,operation,manifest_sha256,preview_sha256,database_identity,source_id,
    expected_counts,authorized_elements,principal_id,nonce,expires_at,status,consumed_at
  ) VALUES(
    v_source_authorization,'reimport',repeat('a',64),repeat('b',64),current_database(),v_ledger_source_id,
    '{"person_creates":1,"source_evidence":0,"canonical_delta":0}',
    jsonb_build_object('person-create:legacy-invalid-terminal',v_source_payload),
    '15300000-0000-4000-8000-000000000206','15300000-0000-4000-8000-000000000207',
    clock_timestamp()+interval '1 hour','consumed',clock_timestamp()
  );
  INSERT INTO private.reimport_1939_write_batch(
    id,authorization_id,manifest_sha256,preview_sha256,principal_id,status,expected_counts,observed_counts,finalized_at
  ) VALUES(
    v_source_id,v_source_authorization,repeat('a',64),repeat('b',64),
    '15300000-0000-4000-8000-000000000206',
    CASE WHEN v_case='reversed_finalized_child' THEN 'reversed' ELSE 'activated' END,
    '{"person_creates":1,"source_evidence":0,"canonical_delta":0}',
    '{"person_creates":1,"source_evidence":0,"canonical_delta":0}',clock_timestamp()
  );
  INSERT INTO private.reimport_1939_write_event(
    batch_id,element_id,operation,source_record_key,canonical_person_id,payload,after_sha256
  ) VALUES(
    v_source_id,'person-create:legacy-invalid-terminal','person_create','legacy-invalid-terminal',153201,
    v_source_payload,repeat('a',64)
  );
  INSERT INTO private.reimport_1939_authorization(
    id,operation,manifest_sha256,preview_sha256,database_identity,source_id,
    expected_counts,authorized_elements,principal_id,nonce,expires_at,status,consumed_at
  ) VALUES(
    v_child_authorization,'name_completion',repeat('c',64),repeat('d',64),current_database(),v_ledger_source_id,
    '{"name_completions":1,"operations":1}',
    jsonb_build_object('payloads',v_payloads,'source_manifest_content_sha256',repeat('a',64)),
    '15300000-0000-4000-8000-000000000206','15300000-0000-4000-8000-000000000209',
    clock_timestamp()+interval '1 hour','consumed',clock_timestamp()
  );
  INSERT INTO private.reimport_1939_write_batch(
    id,authorization_id,manifest_sha256,preview_sha256,principal_id,status,expected_counts,observed_counts,finalized_at
  ) VALUES(
    v_child_id,v_child_authorization,repeat('c',64),repeat('d',64),
    '15300000-0000-4000-8000-000000000206','finalized',
    '{"name_completions":1,"operations":1}','{"name_completions":1,"operations":1}',clock_timestamp()
  );
  INSERT INTO private.reimport_1939_write_event(
    batch_id,element_id,operation,source_record_key,canonical_person_id,payload,after_sha256
  ) VALUES(
    v_child_id,'name-completion:legacy-invalid-terminal','canonical_delta','legacy-invalid-terminal',153201,
    v_payload,v_result_sha256
  );
  INSERT INTO private.reimport_1939_name_completion_result(
    batch_id,element_id,source_batch_id,person_id,source_record_id,source_persona_id,
    fact_id,assertion_id,citation_id,conclusion_id,payload_sha256,result_sha256
  ) VALUES(
    v_child_id,'name-completion:legacy-invalid-terminal',v_source_id,
    CASE WHEN v_case='broken_result' THEN 153299 ELSE 153201 END,
    '15300000-0000-4000-8000-000000000210','15300000-0000-4000-8000-000000000208',
    153202,153203,153204,153205,private.reimport_1939_canonical_json_sha256(v_payload),v_result_sha256
  );
  INSERT INTO private.reimport_1939_authorization(
    id,operation,manifest_sha256,preview_sha256,database_identity,source_id,
    expected_counts,authorized_elements,principal_id,nonce,expires_at,status,consumed_at
  ) VALUES(
    v_terminal_authorization,
    CASE WHEN v_case='reversed_finalized_child' THEN 'reversal' ELSE 'cutover' END,
    repeat('a',64),repeat('b',64),'batch:'||v_source_id::text,v_ledger_source_id,'{}','{}',
    '15300000-0000-4000-8000-000000000206','15300000-0000-4000-8000-000000000211',
    clock_timestamp()+interval '1 hour','consumed',clock_timestamp()
  );
  IF v_case='identity_multi_source' THEN
    INSERT INTO private.reimport_1939_authorization(
      id,operation,manifest_sha256,preview_sha256,database_identity,source_id,
      expected_counts,authorized_elements,principal_id,nonce,expires_at,status,consumed_at
    ) VALUES(
      '15300000-0000-4000-8000-000000000215','cutover',repeat('e',64),repeat('f',64),
      'batch:'||v_source_id::text,4,'{}','{}',
      '15300000-0000-4000-8000-000000000206','15300000-0000-4000-8000-000000000216',
      clock_timestamp()+interval '1 hour','consumed',clock_timestamp()
    );
  END IF;
  IF v_case='ambiguous_child' THEN
    INSERT INTO private.reimport_1939_authorization(
      id,operation,manifest_sha256,preview_sha256,database_identity,source_id,
      expected_counts,authorized_elements,principal_id,nonce,expires_at,status,consumed_at
    ) VALUES(
      '15300000-0000-4000-8000-000000000212','name_completion',repeat('e',64),repeat('f',64),current_database(),3,
      '{"name_completions":1,"operations":1}',
      jsonb_build_object('payloads',v_payloads,'source_manifest_content_sha256',repeat('a',64)),
      '15300000-0000-4000-8000-000000000206','15300000-0000-4000-8000-000000000213',
      clock_timestamp()+interval '1 hour','consumed',clock_timestamp()
    );
    INSERT INTO private.reimport_1939_write_batch(
      id,authorization_id,manifest_sha256,preview_sha256,principal_id,status,expected_counts,observed_counts,finalized_at
    ) VALUES(
      '15300000-0000-4000-8000-000000000214','15300000-0000-4000-8000-000000000212',repeat('e',64),repeat('f',64),
      '15300000-0000-4000-8000-000000000206','finalized',
      '{"name_completions":1,"operations":1}','{"name_completions":1,"operations":1}',clock_timestamp()
    );
  END IF;
END $fixture$;
