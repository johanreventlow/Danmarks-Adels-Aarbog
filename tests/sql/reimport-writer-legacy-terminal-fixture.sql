\set ON_ERROR_STOP on

-- This fixture is intentionally run only against the historical 2d6aabf
-- schema.  It creates a terminal legacy chain through the historic public
-- writer and name-completion RPCs; it never inserts a ledger/event/result row
-- directly.  The marker record keys make the post-migration preservation
-- assertion independent of generated UUIDs and identity-sequence values.
DO $fixture$
DECLARE
  v_actor uuid := '15300000-0000-4000-8000-000000000001';
  v_source_authorization uuid;
  v_source_batch uuid;
  v_completion_authorization uuid;
  v_completion_batch uuid;
  v_cutover_authorization uuid;
  v_reversal_authorization uuid;
  v_source_elements jsonb := '{}'::jsonb;
  v_completion_payloads jsonb := '{}'::jsonb;
  v_source_payload jsonb;
  v_completion_payload jsonb;
  v_activation jsonb;
  v_reversal jsonb;
  v_element text;
  v_record_key text;
  v_persona_id uuid;
  v_person_id bigint;
  v_index integer;
BEGIN
  INSERT INTO public.source(id,titel,udgave,slags)
  VALUES(3,'DAA','1939','DAA-udgave')
  ON CONFLICT(id) DO NOTHING;
  INSERT INTO auth.users(id,email)
  VALUES(v_actor,'legacy-terminal-rpc-153@example.invalid')
  ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.profiles(id,email,rolle,navn)
  VALUES(v_actor,'legacy-terminal-rpc-153@example.invalid','redaktion','Legacy terminal fixture')
  ON CONFLICT(id) DO UPDATE SET rolle='redaktion',navn='Legacy terminal fixture';
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);

  -- First construct the exact authorized envelope.  The eight person-create
  -- calls below are the historic source lifecycle, not synthetic ledger rows.
  FOR v_index IN 1..8 LOOP
    v_record_key := 'legacy-terminal-rpc-153-' || v_index;
    v_element := 'person-create:' || v_record_key;
    v_persona_id := ('15300000-0000-4000-8000-' || lpad(v_index::text,12,'0'))::uuid;
    v_source_payload := jsonb_build_object(
      'source_record_key',v_record_key,
      'source_id',3,
      'edition','1939',
      'source_span',jsonb_build_object('char_from',v_index * 20,'char_to',v_index * 20 + 10),
      'page_evidence',jsonb_build_object('page_from',v_index,'page_to',v_index),
      'verbatim_text','Legacy terminal fixture ' || v_index,
      'verbatim_sha256',encode(extensions.digest(convert_to('Legacy terminal fixture ' || v_index,'UTF8'),'sha256'),'hex'),
      'source_persona_id',v_persona_id,
      'persona_key','1939:' || v_record_key,
      'identity_decision_sha256',repeat('1',64),
      'review_sha256',repeat('2',64),
      'decision_basis','legacy-terminal-rpc-fixture',
      'name','Legacy terminal fixture ' || v_index,
      'sex',NULL,
      'narrative',jsonb_build_object('text','Legacy terminal fixture narrative ' || v_index,'source_record_key',v_record_key),
      'source_mentions','[]'::jsonb,
      'persona_mention_links','[]'::jsonb,
      'facts','[]'::jsonb,
      'relations','[]'::jsonb,
      'families','[]'::jsonb,
      'uncertainties','[]'::jsonb,
      'staged',true,
      'rendition_content_sha256',repeat('3',64)
    );
    v_source_elements := v_source_elements || jsonb_build_object(v_element,v_source_payload);
  END LOOP;

  v_source_authorization := public.red_authorize_1939_v50_reimport(
    repeat('a',64),repeat('b',64),current_database(),3,
    '{"person_creates":8,"source_evidence":0,"canonical_delta":0}'::jsonb,
    v_source_elements,
    '15300000-0000-4000-8000-000000000002',clock_timestamp()+interval '5 minutes'
  );
  v_source_batch := public.red_begin_1939_v50_reimport(
    v_source_authorization,repeat('a',64),repeat('b',64)
  );
  FOR v_index IN 1..8 LOOP
    v_record_key := 'legacy-terminal-rpc-153-' || v_index;
    v_element := 'person-create:' || v_record_key;
    PERFORM public.red_apply_1939_v50_person_create(
      v_source_batch,v_element,v_source_elements->v_element
    );
  END LOOP;
  IF (public.red_finalize_1939_v50_reimport(v_source_batch)->>'status')<>'finalized'
     OR (SELECT count(*) FROM private.reimport_1939_write_event
          WHERE batch_id=v_source_batch AND operation='person_create')<>8 THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_LEGACY_TERMINAL_SOURCE_RPC_FAILED';
  END IF;

  -- The historical name-completion preflight intentionally requires an empty
  -- derived name cache.  The source writer sets this cache during person
  -- creation, so clear only that derived cache before exercising the public
  -- completion RPC.  All ledger, delta and result rows remain RPC-created.
  UPDATE public.person
     SET visning_navn=NULL
   WHERE id IN (
     SELECT canonical_person_id
       FROM private.reimport_1939_write_event
      WHERE batch_id=v_source_batch AND operation='person_create'
   );

  FOR v_index IN 1..8 LOOP
    v_record_key := 'legacy-terminal-rpc-153-' || v_index;
    v_element := 'person-create:' || v_record_key;
    SELECT canonical_person_id INTO v_person_id
      FROM private.reimport_1939_write_event
     WHERE batch_id=v_source_batch AND element_id=v_element AND operation='person_create';
    v_source_payload := v_source_elements->v_element;
    v_completion_payload := jsonb_build_object(
      'source_batch_id',v_source_batch,
      'source_person_create_element_id',v_element,
      'person_id',v_person_id,
      'source_id',3,
      'edition','1939',
      'source_record_key',v_record_key,
      'source_persona_id',v_source_payload->>'source_persona_id',
      'name',v_source_payload->>'name',
      'source_span',v_source_payload->'source_span',
      'page_evidence',v_source_payload->'page_evidence',
      'verbatim_text',v_source_payload->>'verbatim_text',
      'verbatim_sha256',v_source_payload->>'verbatim_sha256',
      'source_payload_sha256',private.reimport_1939_canonical_json_sha256(v_source_payload),
      'expected_before','{"staged":true,"name_cache_empty":true,"name_facts":0}'::jsonb,
      'expected_after','{"name_fact":1,"selected_assertion":1,"daa_1939_citation":1,"conclusion":1}'::jsonb
    );
    v_completion_payloads := v_completion_payloads || jsonb_build_object('name-completion:' || v_record_key,v_completion_payload);
  END LOOP;
  v_completion_authorization := (
    public.red_authorize_1939_v50_name_completion(
      repeat('c',64),v_source_batch,repeat('d',64),repeat('a',64),
      '{"name_completions":8,"operations":8}'::jsonb,v_completion_payloads
    )->>'authorization_id'
  )::uuid;
  PERFORM public.red_preflight_1939_v50_name_completion(
    v_completion_authorization,v_source_batch,repeat('c',64),v_completion_payloads
  );
  v_completion_batch := public.red_begin_1939_v50_name_completion(
    v_completion_authorization,repeat('c',64),v_source_batch
  );
  FOR v_index IN 1..8 LOOP
    v_record_key := 'legacy-terminal-rpc-153-' || v_index;
    v_element := 'name-completion:' || v_record_key;
    PERFORM public.red_apply_1939_v50_name_completion(
      v_completion_batch,v_element,v_completion_payloads->v_element
    );
  END LOOP;
  IF (public.red_finalize_1939_v50_name_completion(v_completion_batch)->>'status')<>'finalized'
     OR (SELECT count(*) FROM private.reimport_1939_write_event
          WHERE batch_id=v_completion_batch AND operation='canonical_delta')<>8
     OR (SELECT count(*) FROM private.reimport_1939_name_completion_result
          WHERE batch_id=v_completion_batch AND source_batch_id=v_source_batch)<>8 THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_LEGACY_TERMINAL_COMPLETION_RPC_FAILED';
  END IF;

  -- Activation is the historic terminal transition that preserves the
  -- finalized child while removing all executable reimport work.
  v_cutover_authorization := public.red_authorize_1939_v50_cutover(
    v_source_batch,'15300000-0000-4000-8000-000000000003',clock_timestamp()+interval '5 minutes'
  );
  v_activation := public.red_activate_1939_v50_batch(v_source_batch,v_cutover_authorization);
  IF (v_activation->>'status')<>'activated'
     OR (SELECT status FROM private.reimport_1939_write_batch WHERE id=v_source_batch)<>'activated'
     OR (SELECT status FROM private.reimport_1939_write_batch WHERE id=v_completion_batch)<>'finalized'
     OR (SELECT status FROM private.reimport_1939_authorization WHERE id=v_source_authorization)<>'consumed'
     OR (SELECT status FROM private.reimport_1939_authorization WHERE id=v_completion_authorization)<>'consumed'
     OR (SELECT count(*) FROM private.reimport_1939_write_event
          WHERE batch_id=v_completion_batch AND operation='canonical_delta')<>8
     OR (SELECT count(*) FROM private.reimport_1939_name_completion_result
          WHERE batch_id=v_completion_batch AND source_batch_id=v_source_batch)<>8 THEN
    RAISE EXCEPTION USING
      MESSAGE='REIMPORT_WRITER_LEGACY_TERMINAL_ACTIVATION_FAILED',
      DETAIL=jsonb_build_object(
        'activation',v_activation,
        'source_status',(SELECT status FROM private.reimport_1939_write_batch WHERE id=v_source_batch),
        'completion_status',(SELECT status FROM private.reimport_1939_write_batch WHERE id=v_completion_batch),
        'source_authorization_status',(SELECT status FROM private.reimport_1939_authorization WHERE id=v_source_authorization),
        'completion_authorization_status',(SELECT status FROM private.reimport_1939_authorization WHERE id=v_completion_authorization),
        'canonical_delta_count',(SELECT count(*) FROM private.reimport_1939_write_event WHERE batch_id=v_completion_batch AND operation='canonical_delta'),
        'result_count',(SELECT count(*) FROM private.reimport_1939_name_completion_result WHERE batch_id=v_completion_batch AND source_batch_id=v_source_batch)
      )::text;
  END IF;

  -- Build the second historical terminal form with the same public v1 RPC
  -- lifecycle.  In this form the source and its completion child are both
  -- reversed by the old reversal RPC; it retains the immutable child result,
  -- event and authorization ledgers while reversing their application state.
  v_source_elements := '{}'::jsonb;
  v_completion_payloads := '{}'::jsonb;
  FOR v_index IN 1..8 LOOP
    v_record_key := 'legacy-terminal-rpc-153-reversed-' || v_index;
    v_element := 'person-create:' || v_record_key;
    v_persona_id := ('15300000-0000-4000-8000-' || lpad((100+v_index)::text,12,'0'))::uuid;
    v_source_payload := jsonb_build_object(
      'source_record_key',v_record_key,
      'source_id',3,
      'edition','1939',
      'source_span',jsonb_build_object('char_from',1000 + v_index * 20,'char_to',1000 + v_index * 20 + 10),
      'page_evidence',jsonb_build_object('page_from',100 + v_index,'page_to',100 + v_index),
      'verbatim_text','Legacy reversed terminal fixture ' || v_index,
      'verbatim_sha256',encode(extensions.digest(convert_to('Legacy reversed terminal fixture ' || v_index,'UTF8'),'sha256'),'hex'),
      'source_persona_id',v_persona_id,
      'persona_key','1939:' || v_record_key,
      'identity_decision_sha256',repeat('1',64),
      'review_sha256',repeat('2',64),
      'decision_basis','legacy-terminal-rpc-fixture',
      'name','Legacy reversed terminal fixture ' || v_index,
      'sex',NULL,
      'narrative',jsonb_build_object('text','Legacy reversed terminal fixture narrative ' || v_index,'source_record_key',v_record_key),
      'source_mentions','[]'::jsonb,
      'persona_mention_links','[]'::jsonb,
      'facts','[]'::jsonb,
      'relations','[]'::jsonb,
      'families','[]'::jsonb,
      'uncertainties','[]'::jsonb,
      'staged',true,
      'rendition_content_sha256',repeat('3',64)
    );
    v_source_elements := v_source_elements || jsonb_build_object(v_element,v_source_payload);
  END LOOP;
  v_source_authorization := public.red_authorize_1939_v50_reimport(
    repeat('e',64),repeat('f',64),current_database(),3,
    '{"person_creates":8,"source_evidence":0,"canonical_delta":0}'::jsonb,
    v_source_elements,
    '15300000-0000-4000-8000-000000000004',clock_timestamp()+interval '5 minutes'
  );
  v_source_batch := public.red_begin_1939_v50_reimport(
    v_source_authorization,repeat('e',64),repeat('f',64)
  );
  FOR v_index IN 1..8 LOOP
    v_record_key := 'legacy-terminal-rpc-153-reversed-' || v_index;
    v_element := 'person-create:' || v_record_key;
    PERFORM public.red_apply_1939_v50_person_create(
      v_source_batch,v_element,v_source_elements->v_element
    );
  END LOOP;
  IF (public.red_finalize_1939_v50_reimport(v_source_batch)->>'status')<>'finalized'
     OR (SELECT count(*) FROM private.reimport_1939_write_event
          WHERE batch_id=v_source_batch AND operation='person_create')<>8 THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_LEGACY_REVERSED_SOURCE_RPC_FAILED';
  END IF;

  UPDATE public.person
     SET visning_navn=NULL
   WHERE id IN (
     SELECT canonical_person_id
       FROM private.reimport_1939_write_event
      WHERE batch_id=v_source_batch AND operation='person_create'
   );
  FOR v_index IN 1..8 LOOP
    v_record_key := 'legacy-terminal-rpc-153-reversed-' || v_index;
    v_element := 'person-create:' || v_record_key;
    SELECT canonical_person_id INTO v_person_id
      FROM private.reimport_1939_write_event
     WHERE batch_id=v_source_batch AND element_id=v_element AND operation='person_create';
    v_source_payload := v_source_elements->v_element;
    v_completion_payload := jsonb_build_object(
      'source_batch_id',v_source_batch,
      'source_person_create_element_id',v_element,
      'person_id',v_person_id,
      'source_id',3,
      'edition','1939',
      'source_record_key',v_record_key,
      'source_persona_id',v_source_payload->>'source_persona_id',
      'name',v_source_payload->>'name',
      'source_span',v_source_payload->'source_span',
      'page_evidence',v_source_payload->'page_evidence',
      'verbatim_text',v_source_payload->>'verbatim_text',
      'verbatim_sha256',v_source_payload->>'verbatim_sha256',
      'source_payload_sha256',private.reimport_1939_canonical_json_sha256(v_source_payload),
      'expected_before','{"staged":true,"name_cache_empty":true,"name_facts":0}'::jsonb,
      'expected_after','{"name_fact":1,"selected_assertion":1,"daa_1939_citation":1,"conclusion":1}'::jsonb
    );
    v_completion_payloads := v_completion_payloads || jsonb_build_object('name-completion:' || v_record_key,v_completion_payload);
  END LOOP;
  v_completion_authorization := (
    public.red_authorize_1939_v50_name_completion(
      repeat('c',64),v_source_batch,repeat('d',64),repeat('e',64),
      '{"name_completions":8,"operations":8}'::jsonb,v_completion_payloads
    )->>'authorization_id'
  )::uuid;
  PERFORM public.red_preflight_1939_v50_name_completion(
    v_completion_authorization,v_source_batch,repeat('c',64),v_completion_payloads
  );
  v_completion_batch := public.red_begin_1939_v50_name_completion(
    v_completion_authorization,repeat('c',64),v_source_batch
  );
  FOR v_index IN 1..8 LOOP
    v_record_key := 'legacy-terminal-rpc-153-reversed-' || v_index;
    v_element := 'name-completion:' || v_record_key;
    PERFORM public.red_apply_1939_v50_name_completion(
      v_completion_batch,v_element,v_completion_payloads->v_element
    );
  END LOOP;
  IF (public.red_finalize_1939_v50_name_completion(v_completion_batch)->>'status')<>'finalized'
     OR (SELECT count(*) FROM private.reimport_1939_write_event
          WHERE batch_id=v_completion_batch AND operation='canonical_delta')<>8
     OR (SELECT count(*) FROM private.reimport_1939_name_completion_result
          WHERE batch_id=v_completion_batch AND source_batch_id=v_source_batch)<>8 THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_LEGACY_REVERSED_COMPLETION_RPC_FAILED';
  END IF;
  v_reversal_authorization := public.red_authorize_1939_v50_reversal(
    v_source_batch,'15300000-0000-4000-8000-000000000005',clock_timestamp()+interval '5 minutes'
  );
  v_reversal := public.red_reverse_1939_v50_reimport(v_source_batch,v_reversal_authorization);
  IF (v_reversal->>'status')<>'reversed'
     OR (SELECT status FROM private.reimport_1939_write_batch WHERE id=v_source_batch)<>'reversed'
     OR (SELECT status FROM private.reimport_1939_write_batch WHERE id=v_completion_batch)<>'reversed'
     OR (SELECT status FROM private.reimport_1939_authorization WHERE id=v_source_authorization)<>'consumed'
     OR (SELECT status FROM private.reimport_1939_authorization WHERE id=v_completion_authorization)<>'consumed'
     OR (SELECT status FROM private.reimport_1939_authorization WHERE id=v_reversal_authorization)<>'consumed'
     OR (SELECT count(*) FROM private.reimport_1939_name_completion_result WHERE batch_id=v_completion_batch)<>8
     OR (SELECT count(*) FROM private.reimport_1939_write_event
          WHERE batch_id=v_completion_batch AND operation='canonical_delta')<>8 THEN
    RAISE EXCEPTION USING
      MESSAGE='REIMPORT_WRITER_LEGACY_TERMINAL_REVERSAL_FAILED',
      DETAIL=jsonb_build_object(
        'reversal',v_reversal,
        'source_status',(SELECT status FROM private.reimport_1939_write_batch WHERE id=v_source_batch),
        'completion_status',(SELECT status FROM private.reimport_1939_write_batch WHERE id=v_completion_batch),
        'source_authorization_status',(SELECT status FROM private.reimport_1939_authorization WHERE id=v_source_authorization),
        'completion_authorization_status',(SELECT status FROM private.reimport_1939_authorization WHERE id=v_completion_authorization),
        'reversal_authorization_status',(SELECT status FROM private.reimport_1939_authorization WHERE id=v_reversal_authorization),
        'completion_result_count',(SELECT count(*) FROM private.reimport_1939_name_completion_result WHERE batch_id=v_completion_batch),
        'canonical_delta_count',(SELECT count(*) FROM private.reimport_1939_write_event WHERE batch_id=v_completion_batch AND operation='canonical_delta')
      )::text;
  END IF;
END $fixture$;
