-- Trin 6b Task 2: writer-operationen publication_persona (red_apply_reimport_publication_persona).
-- Kræver kontrakt v2 (reimport-writer-v2-bootstrap.sql) som test-publication-registration.sql. Alt syntetisk; én
-- transaktion, rulles tilbage.
\set ON_ERROR_STOP on
\i tests/sql/fixtures/publication-persona.sql
BEGIN;
-- pg_temp-funktionerne ligger i sessionen og overlever transaktionen; de oprettes uden for den.

CREATE FUNCTION pg_temp.expect_apply(p_src jsonb, p_batch uuid, p_element text, p_payload jsonb, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN PERFORM pg_temp.pp_apply(p_src,p_batch,p_element,p_payload);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM IS NULL OR SQLERRM NOT LIKE p_token||'%' THEN
      RAISE EXCEPTION 'PUBLICATION_PERSONA_TEST_WRONG_ERROR: element % expected % got %', p_element, p_token, SQLERRM; END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'PUBLICATION_PERSONA_TEST_NO_ERROR: element % expected %', p_element, p_token;
END $$;

CREATE FUNCTION pg_temp.el(p_key text) RETURNS text LANGUAGE sql AS $$ SELECT 'publication-persona:'||p_key $$;

DO $pp$
DECLARE
  v_src jsonb:=pg_temp.pp_source(-6210,'11000000-0000-0000-0000-00000006b201');
  v_hp jsonb; v_ma jsonb; v_am jsonb; v_out jsonb; v_md jsonb; v_bd1 jsonb; v_bd2 jsonb; v_bd3 jsonb; v_bd4 jsonb; v_se jsonb;
  v_ex jsonb; v_ex2 jsonb; v_pi jsonb;
  v_payload jsonb; v_els jsonb:='{}'::jsonb; v_batch uuid; v_receipt jsonb; v_state_before jsonb; v_persona uuid;
  v_event private.reimport_event%ROWTYPE; v_dummy_persona uuid; v_n bigint;
BEGIN
  v_hp:=pg_temp.pp_post(v_src,'hp',-621001);
  v_ma:=pg_temp.pp_post(v_src,'ma',-621002,'{"subs":2}');
  v_am:=pg_temp.pp_post(v_src,'am',-621003);
  PERFORM pg_temp.pp_occ((v_am->>'record')::uuid,v_src,'am-h2',600,900,'person');
  v_out:=pg_temp.pp_post(v_src,'out',-621004,'{"subs":2}');
  PERFORM pg_temp.pp_occ((v_out->>'record')::uuid,v_src,'out-s3',480,520,'fact');
  v_md:=pg_temp.pp_post(v_src,'md',-621005);
  v_bd1:=pg_temp.pp_post(v_src,'bd1',-621006,'{"binding":"draft"}');
  v_bd2:=pg_temp.pp_post(v_src,'bd2',-621007);
  v_bd3:=pg_temp.pp_post(v_src,'bd3',-621008);
  v_bd4:=pg_temp.pp_post(v_src,'bd4',-621009,'{"binding":"withdrawn+published"}');
  v_se:=pg_temp.pp_post(v_src,'se',-621010,'{"ext_ids":0}');
  v_ex:=pg_temp.pp_post(v_src,'ex',-621011);
  v_ex2:=pg_temp.pp_post(v_src,'ex2',-621012);
  v_pi:=pg_temp.pp_post(v_src,'pi',-621013);

  -- "to published" kan kun opstå direkte i fixturen: den aktive-binding-index spærrer det ellers.
  DROP INDEX private.narrative_record_publication_active_record_uidx;
  INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst) VALUES ('person',-621007,-6210,'1','anden') RETURNING id INTO v_n;
  INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status)
    VALUES (v_n,(v_bd2->>'record')::uuid,'to','to','published');
  -- v50-lignende persona: anden nøgleform, mention på helposten
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES (-6210,'ex-anden-form',(v_src->>'run')::uuid) RETURNING id INTO v_dummy_persona;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_dummy_persona,(v_ex->>'mention')::uuid,'primary',1);
  -- persona med netop nøglen, uden mention
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES (-6210,'1939:ex2',(v_src->>'run')::uuid);

  -- Elementer: alle autoriserede payloads (drift-varianter er selv autoriserede, så afvisningen kommer fra writeren).
  v_els:=jsonb_build_object(
    pg_temp.el('hp'),pg_temp.pp_payload(v_src,v_hp), pg_temp.el('ma'),pg_temp.pp_payload(v_src,v_ma),
    pg_temp.el('am'),pg_temp.pp_payload(v_src,v_am), pg_temp.el('out'),pg_temp.pp_payload(v_src,v_out),
    pg_temp.el('md'),pg_temp.pp_payload(v_src,v_md)||jsonb_build_object('mention_text_sha256',repeat('0',64)),
    pg_temp.el('bd1'),pg_temp.pp_payload(v_src,v_bd1), pg_temp.el('bd2'),pg_temp.pp_payload(v_src,v_bd2),
    pg_temp.el('bd3'),pg_temp.pp_payload(v_src,v_bd3)||jsonb_build_object('binding_id',gen_random_uuid()),
    pg_temp.el('bd4'),pg_temp.pp_payload(v_src,v_bd4), pg_temp.el('se'),pg_temp.pp_payload(v_src,v_se),
    pg_temp.el('ex'),pg_temp.pp_payload(v_src,v_ex), pg_temp.el('ex2'),pg_temp.pp_payload(v_src,v_ex2),
    pg_temp.el('pi'),pg_temp.pp_payload(v_src,v_pi)||jsonb_build_object('extra','x'),
    pg_temp.el('rm'),pg_temp.pp_payload(v_src,v_pi)||jsonb_build_object('source_record_key','rm','persona_key','1939:rm'),
    pg_temp.el('pi2'),pg_temp.pp_payload(v_src,v_pi)||jsonb_build_object('source_record_key','pi2'),
    pg_temp.el('pi3'),pg_temp.pp_payload(v_src,v_pi)||jsonb_build_object('source_record_key','pi3','persona_key','1939:pi3','binding_status','draft'));
  v_batch:=pg_temp.pp_begin(v_src,'fixture-pub-a','main',v_els);

  -- happy_path + narrative_state_unchanged
  v_state_before:=private.narrative_publication_state(-621001,-6210,'hp');
  v_receipt:=pg_temp.pp_apply(v_src,v_batch,pg_temp.el('hp'),v_els->pg_temp.el('hp'));
  v_persona:=private.content_uuid('source-persona',jsonb_build_object('source_id',-6210,'persona_key','1939:hp'));
  IF v_receipt IS DISTINCT FROM jsonb_build_object('source_persona_id',v_persona,'mention_id',v_hp->>'mention','binding_id',v_hp->>'binding','person_id',-621001) THEN
    RAISE EXCEPTION 'PUBLICATION_PERSONA_TEST_RECEIPT: %',v_receipt; END IF;
  IF (SELECT count(*) FROM private.source_persona WHERE id=v_persona AND source_id=-6210 AND persona_key='1939:hp')<>1
     OR (SELECT count(*) FROM private.source_persona_mention WHERE persona_id=v_persona AND mention_id=(v_hp->>'mention')::uuid
          AND mention_role='primary' AND ordinal=1)<>1
     OR (SELECT count(*) FROM private.source_persona_mention WHERE persona_id=v_persona)<>1 THEN
    RAISE EXCEPTION 'PUBLICATION_PERSONA_TEST_HAPPY_ROWS'; END IF;
  IF EXISTS (SELECT 1 FROM private.source_persona_identity WHERE source_persona_id=v_persona) THEN
    RAISE EXCEPTION 'PUBLICATION_PERSONA_TEST_IDENTITY_WRITTEN'; END IF;
  SELECT * INTO v_event FROM private.reimport_event WHERE batch_id=v_batch AND element_id=pg_temp.el('hp');
  IF v_event.operation<>'publication_persona' OR v_event.canonical_person_id<>-621001 OR v_event.source_record_key<>'hp'
     OR v_event.payload->'result_receipt' IS DISTINCT FROM v_receipt
     OR v_event.after_sha256<>private.reimport_canonical_json_sha256(v_receipt)
     OR (v_event.payload-'result_receipt') IS DISTINCT FROM (v_els->pg_temp.el('hp')) THEN
    RAISE EXCEPTION 'PUBLICATION_PERSONA_TEST_EVENT'; END IF;
  IF private.narrative_publication_state(-621001,-6210,'hp') IS DISTINCT FROM v_state_before THEN
    RAISE EXCEPTION 'PUBLICATION_PERSONA_TEST_STATE_CHANGED'; END IF;
  RAISE NOTICE 'OK: happy_path, narrative_state_unchanged';

  -- replay af samme element: UNIQUE(batch_id,element_id), ingen anden persona
  BEGIN
    PERFORM pg_temp.pp_apply(v_src,v_batch,pg_temp.el('hp'),v_els->pg_temp.el('hp'));
    RAISE EXCEPTION 'PUBLICATION_PERSONA_TEST_REPLAY_ACCEPTED';
  EXCEPTION WHEN unique_violation OR OTHERS THEN
    IF SQLERRM LIKE 'PUBLICATION_PERSONA_TEST%' THEN RAISE; END IF;
  END;
  IF (SELECT count(*) FROM private.source_persona WHERE source_id=-6210 AND persona_key='1939:hp')<>1 THEN
    RAISE EXCEPTION 'PUBLICATION_PERSONA_TEST_REPLAY_DOUBLE'; END IF;
  RAISE NOTICE 'OK: replay element';

  -- multi_anchor
  PERFORM pg_temp.pp_apply(v_src,v_batch,pg_temp.el('ma'),v_els->pg_temp.el('ma'));
  IF (SELECT count(*) FROM private.source_persona_mention WHERE mention_id=(v_ma->>'mention')::uuid AND mention_role='primary')<>1 THEN
    RAISE EXCEPTION 'PUBLICATION_PERSONA_TEST_MULTI_ANCHOR'; END IF;
  RAISE NOTICE 'OK: multi_anchor';

  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('am'),v_els->pg_temp.el('am'),'RECORD_HELPOST_AMBIGUOUS');
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('out'),v_els->pg_temp.el('out'),'RECORD_HELPOST_SUBOCCURRENCE_OUTSIDE');
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('md'),v_els->pg_temp.el('md'),'PUBLICATION_PERSONA_MENTION_DRIFT');
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('bd1'),v_els->pg_temp.el('bd1'),'PUBLICATION_PERSONA_BINDING_DRIFT');
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('bd2'),v_els->pg_temp.el('bd2'),'PUBLICATION_PERSONA_BINDING_DRIFT');
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('bd3'),v_els->pg_temp.el('bd3'),'PUBLICATION_PERSONA_BINDING_DRIFT');
  PERFORM pg_temp.pp_apply(v_src,v_batch,pg_temp.el('bd4'),v_els->pg_temp.el('bd4'));  -- withdrawn + én published lykkes
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('se'),v_els->pg_temp.el('se'),'PUBLICATION_PERSONA_SUBJECT_INVALID');
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('ex'),v_els->pg_temp.el('ex'),'PUBLICATION_PERSONA_EXISTS');
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('ex2'),v_els->pg_temp.el('ex2'),'PUBLICATION_PERSONA_EXISTS');
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('pi'),v_els->pg_temp.el('pi'),'PUBLICATION_PERSONA_PAYLOAD_INVALID');
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('pi2'),v_els->pg_temp.el('pi2'),'PUBLICATION_PERSONA_PAYLOAD_INVALID');  -- persona_key passer ikke
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('pi3'),v_els->pg_temp.el('pi3'),'PUBLICATION_PERSONA_PAYLOAD_INVALID');  -- binding_status draft
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('rm'),v_els->pg_temp.el('rm'),'PUBLICATION_PERSONA_RECORD_MISSING');
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('hp'),(v_els->pg_temp.el('md')),'REIMPORT_WRITER_ELEMENT_NOT_AUTHORIZED'); -- payload ≠ autoriseret
  -- ingen af afvisningerne har skrevet noget
  IF (SELECT count(*) FROM private.reimport_event WHERE batch_id=v_batch)<>3
     OR (SELECT count(*) FROM private.source_persona WHERE source_id=-6210 AND persona_key LIKE '1939:%' AND persona_key<>'1939:ex2')<>3 THEN
    RAISE EXCEPTION 'PUBLICATION_PERSONA_TEST_REJECTIONS_WROTE'; END IF;
  RAISE NOTICE 'OK: rejections (helpost, mention_drift, binding_drift, subject, exists, payload, record_missing, authorization)';

  -- rettigheder
  IF has_function_privilege('anon','public.red_apply_reimport_publication_persona(uuid,text,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_apply_reimport_publication_persona(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.write_publication_persona(uuid,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'PUBLICATION_PERSONA_TEST_PRIVILEGES'; END IF;
END $pp$;

-- full_chain: authorize → begin → apply → finalize med to elementer, og replay af samme manifest.
DO $chain$
DECLARE
  v_src jsonb:=pg_temp.pp_source(-6211,'11000000-0000-0000-0000-00000006b202');
  v_a jsonb; v_b jsonb; v_els jsonb; v_batch uuid; v_again uuid; v_final jsonb;
BEGIN
  v_a:=pg_temp.pp_post(v_src,'ca',-621101); v_b:=pg_temp.pp_post(v_src,'cb',-621102,'{"subs":2}');
  v_els:=jsonb_build_object(pg_temp.el('ca'),pg_temp.pp_payload(v_src,v_a),pg_temp.el('cb'),pg_temp.pp_payload(v_src,v_b));
  v_batch:=pg_temp.pp_begin(v_src,'fixture-pub-a','chain',v_els);
  PERFORM pg_temp.pp_apply(v_src,v_batch,pg_temp.el('ca'),v_els->pg_temp.el('ca'));
  PERFORM pg_temp.pp_apply(v_src,v_batch,pg_temp.el('cb'),v_els->pg_temp.el('cb'));
  PERFORM set_config('request.jwt.claim.sub',v_src->>'actor',true); PERFORM set_config('role','authenticated',true);
  v_final:=public.red_finalize_reimport(v_batch);
  RESET role;
  IF v_final->>'status'<>'finalized' OR (v_final->'counts'->>'publication_personas')::int<>2
     OR (SELECT observed_counts->>'publication_personas' FROM private.reimport_batch WHERE id=v_batch)<>'2' THEN
    RAISE EXCEPTION 'PUBLICATION_PERSONA_TEST_FINALIZE: %',v_final; END IF;
  -- efter finalize giver samme manifest og preview (ny autorisation) den eksisterende batch igen (6a's already_applied), og intet skrives to gange
  v_again:=pg_temp.pp_begin(v_src,'fixture-pub-a','chain',v_els);
  IF v_again<>v_batch THEN RAISE EXCEPTION 'PUBLICATION_PERSONA_TEST_REPLAY_AFTER_FINALIZE'; END IF;
  IF (SELECT count(*) FROM private.source_persona WHERE source_id=-6211)<>2 THEN
    RAISE EXCEPTION 'PUBLICATION_PERSONA_TEST_CHAIN_PERSONAS'; END IF;
  RAISE NOTICE 'OK: full_chain';
END $chain$;

ROLLBACK;
