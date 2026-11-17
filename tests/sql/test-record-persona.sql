-- Writer-operationen record_persona (red_apply_reimport_record_persona): persona for en helpost uden aktiv tekstbinding.
-- Kræver kontrakt v2 (reimport-writer-v2-bootstrap.sql) som test-record-persona-registration.sql. Alt syntetisk med
-- negative id'er; én transaktion, rulles tilbage.
\set ON_ERROR_STOP on
\i tests/sql/fixtures/publication-persona.sql
\i tests/sql/fixtures/record-persona.sql
BEGIN;
-- pg_temp-funktionerne ligger i sessionen og overlever transaktionen; de oprettes uden for den.

CREATE FUNCTION pg_temp.expect_apply(p_src jsonb, p_batch uuid, p_element text, p_payload jsonb, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN PERFORM pg_temp.rp_apply(p_src,p_batch,p_element,p_payload);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM IS NULL OR SQLERRM NOT LIKE p_token||'%' THEN
      RAISE EXCEPTION 'RECORD_PERSONA_TEST_WRONG_ERROR: element % expected % got %', p_element, p_token, SQLERRM; END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'RECORD_PERSONA_TEST_NO_ERROR: element % expected %', p_element, p_token;
END $$;

CREATE FUNCTION pg_temp.el(p_key text) RETURNS text LANGUAGE sql AS $$ SELECT 'record-persona:'||p_key $$;

DO $rp$
DECLARE
  v_src jsonb:=pg_temp.pp_source(-6310,'11000000-0000-0000-0000-0000000c0721');
  v_hp jsonb; v_bdd jsonb; v_bdp jsonb; v_bdw jsonb; v_md jsonb; v_mi jsonb; v_mm jsonb; v_am jsonb; v_out jsonb;
  v_sl jsonb; v_se jsonb; v_ex jsonb; v_ex2 jsonb; v_pi jsonb; v_np jsonb;
  v_els jsonb; v_batch uuid; v_batch_n uuid; v_receipt jsonb; v_state_before jsonb; v_persona uuid; v_dummy uuid;
  v_event private.reimport_event%ROWTYPE; v_cname text; v_sheet text:=encode(extensions.digest('rp-sheet','sha256'),'hex');
BEGIN
  INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES (-6319,'Fixture rp anden','synthetic','1900','DAA-udgave');
  v_hp:=pg_temp.rp_post(v_src,'hp',-631001);
  v_bdd:=pg_temp.rp_post(v_src,'bdd',-631002,'{"binding":"draft"}');
  v_bdp:=pg_temp.rp_post(v_src,'bdp',-631003,'{"binding":"published"}');
  v_bdw:=pg_temp.rp_post(v_src,'bdw',-631004,'{"binding":"withdrawn"}');
  v_md:=pg_temp.rp_post(v_src,'md',-631005);
  v_mi:=pg_temp.rp_post(v_src,'mi',-631006);
  v_mm:=pg_temp.rp_post(v_src,'mm',-631007);
  INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
    VALUES ((v_mm->>'observation')::uuid,'person',20,25,rpad('',5,'x'),(v_src->>'run')::uuid);
  v_am:=pg_temp.rp_post(v_src,'am',-631008);
  PERFORM pg_temp.pp_occ((v_am->>'record')::uuid,v_src,'am-h2',600,900,'person');
  v_out:=pg_temp.rp_post(v_src,'out',-631009,'{"subs":2}');
  PERFORM pg_temp.pp_occ((v_out->>'record')::uuid,v_src,'out-s3',480,520,'fact');
  v_sl:=pg_temp.rp_post(v_src,'sl',-631010,'{"levende":true}');
  v_se:=pg_temp.rp_post(v_src,'se',-631011,'{"ext_ids":0,"ext_other":-6319}');
  v_ex:=pg_temp.rp_post(v_src,'ex',-631012);
  v_ex2:=pg_temp.rp_post(v_src,'ex2',-631013);
  v_pi:=pg_temp.rp_post(v_src,'pi',-631014);
  v_np:=pg_temp.rp_post(v_src,'np',-631015);
  -- persona i en anden nøgleform med mention på helposten; persona med netop nøglen, uden mention
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES (-6310,'ex-anden-form',(v_src->>'run')::uuid) RETURNING id INTO v_dummy;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_dummy,(v_ex->>'mention')::uuid,'primary',1);
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES (-6310,'1939:ex2',(v_src->>'run')::uuid);

  -- Alle payloads er autoriserede (drift-varianter er selv autoriserede, så afvisningen kommer fra writeren).
  v_els:=jsonb_build_object(
    pg_temp.el('hp'),pg_temp.rp_payload(v_src,v_hp),
    pg_temp.el('bdd'),pg_temp.rp_payload(v_src,v_bdd), pg_temp.el('bdp'),pg_temp.rp_payload(v_src,v_bdp),
    pg_temp.el('bdw'),pg_temp.rp_payload(v_src,v_bdw),
    pg_temp.el('md'),pg_temp.rp_payload(v_src,v_md)||jsonb_build_object('mention_text_sha256',repeat('0',64)),
    pg_temp.el('mi'),pg_temp.rp_payload(v_src,v_mi)||jsonb_build_object('mention_id',gen_random_uuid()),
    pg_temp.el('mm'),pg_temp.rp_payload(v_src,v_mm),
    pg_temp.el('am'),pg_temp.rp_payload(v_src,v_am), pg_temp.el('out'),pg_temp.rp_payload(v_src,v_out),
    pg_temp.el('sl'),pg_temp.rp_payload(v_src,v_sl), pg_temp.el('se'),pg_temp.rp_payload(v_src,v_se),
    pg_temp.el('ex'),pg_temp.rp_payload(v_src,v_ex), pg_temp.el('ex2'),pg_temp.rp_payload(v_src,v_ex2),
    pg_temp.el('pi'),pg_temp.rp_payload(v_src,v_pi)-'sheet_sha256',
    pg_temp.el('pi2'),pg_temp.rp_payload(v_src,v_pi)||jsonb_build_object('source_record_key','pi2'),
    pg_temp.el('pi3'),pg_temp.rp_payload(v_src,v_pi)||jsonb_build_object('source_record_key','pi3','persona_key','1940:pi3'),
    pg_temp.el('pi4'),pg_temp.rp_payload(v_src,v_pi)||jsonb_build_object('source_record_key','pi4','persona_key','1939:pi4','extra','x'),
    pg_temp.el('pi5'),pg_temp.rp_payload(v_src,v_pi)||jsonb_build_object('source_record_key','pi5','persona_key','1939:pi5','sheet_sha256','XYZ'),
    pg_temp.el('pi6'),pg_temp.rp_payload(v_src,v_pi)||jsonb_build_object('source_record_key','pi6','persona_key','1939:pi6','sheet_line',0),
    pg_temp.el('pi7'),pg_temp.rp_payload(v_src,v_pi)||jsonb_build_object('source_record_key','pi7','persona_key','1939:pi7','sheet_line','1'),
    pg_temp.el('pi8'),pg_temp.rp_payload(v_src,v_pi)||jsonb_build_object('source_record_key','pi8','persona_key','1939:pi8','binding_id',gen_random_uuid()),
    pg_temp.el('pi9'),pg_temp.rp_payload(v_src,v_pi)||jsonb_build_object('source_id',-6319),
    pg_temp.el('rm'),pg_temp.rp_payload(v_src,v_pi)||jsonb_build_object('source_record_key','rm','persona_key','1939:rm'));
  v_batch:=pg_temp.rp_begin(v_src,'fixture-pub-a','main',v_els);

  -- happy_path: persona med indholds-id og nøgle <prefix><record_key>, én primary-mention, ingen identitet, kvittering
  v_state_before:=private.narrative_publication_state(-631001,-6310,'hp');
  IF v_state_before#>>'{authority,kind}'<>'missing_identity' THEN RAISE EXCEPTION 'RECORD_PERSONA_TEST_PRECONDITION: %',v_state_before->'authority'; END IF;
  v_receipt:=pg_temp.rp_apply(v_src,v_batch,pg_temp.el('hp'),v_els->pg_temp.el('hp'));
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v_persona:=private.content_uuid('source-persona',jsonb_build_object('source_id',-6310,'persona_key','1939:hp'));
  IF v_receipt IS DISTINCT FROM jsonb_build_object('source_persona_id',v_persona,'mention_id',v_hp->>'mention','person_id',-631001,
                                                   'sheet_sha256',v_sheet) THEN
    RAISE EXCEPTION 'RECORD_PERSONA_TEST_RECEIPT: %',v_receipt; END IF;
  IF (SELECT count(*) FROM private.source_persona WHERE id=v_persona AND source_id=-6310 AND persona_key='1939:hp')<>1
     OR (SELECT count(*) FROM private.source_persona_mention WHERE persona_id=v_persona AND mention_id=(v_hp->>'mention')::uuid
          AND mention_role='primary' AND ordinal=1)<>1
     OR (SELECT count(*) FROM private.source_persona_mention WHERE persona_id=v_persona)<>1 THEN
    RAISE EXCEPTION 'RECORD_PERSONA_TEST_HAPPY_ROWS'; END IF;
  IF EXISTS (SELECT 1 FROM private.source_persona_identity WHERE source_persona_id=v_persona)
     OR EXISTS (SELECT 1 FROM private.source_persona_placement WHERE source_persona_id=v_persona) THEN
    RAISE EXCEPTION 'RECORD_PERSONA_TEST_IDENTITY_OR_PLACEMENT_WRITTEN'; END IF;
  SELECT * INTO v_event FROM private.reimport_event WHERE batch_id=v_batch AND element_id=pg_temp.el('hp');
  IF v_event.operation<>'record_persona' OR v_event.canonical_person_id<>-631001 OR v_event.source_record_key<>'hp'
     OR v_event.payload->'result_receipt' IS DISTINCT FROM v_receipt
     OR v_event.after_sha256<>private.reimport_canonical_json_sha256(v_receipt)
     OR (v_event.payload-'result_receipt') IS DISTINCT FROM (v_els->pg_temp.el('hp')) THEN
    RAISE EXCEPTION 'RECORD_PERSONA_TEST_EVENT'; END IF;
  IF private.narrative_publication_state(-631001,-6310,'hp') IS DISTINCT FROM v_state_before THEN
    RAISE EXCEPTION 'RECORD_PERSONA_TEST_STATE_CHANGED'; END IF;
  RAISE NOTICE 'OK: happy_path (persona, mention, kvittering, ingen identitet/placement, narrativtilstand stadig missing_identity)';

  -- replay af samme element: EXISTS fra writeren, UNIQUE(batch_id,element_id) som bagstop
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('hp'),v_els->pg_temp.el('hp'),'RECORD_PERSONA_EXISTS');
  BEGIN
    INSERT INTO private.reimport_event(batch_id,element_id,operation,source_record_key,payload,after_sha256)
    VALUES (v_batch,pg_temp.el('hp'),'record_persona','hp','{}'::jsonb,repeat('a',64));
    RAISE EXCEPTION 'RECORD_PERSONA_TEST_REPLAY_ACCEPTED';
  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_cname=CONSTRAINT_NAME;
    IF v_cname IS DISTINCT FROM 'reimport_event_batch_id_element_id_key' THEN
      RAISE EXCEPTION 'RECORD_PERSONA_TEST_REPLAY_WRONG_CONSTRAINT: %',v_cname; END IF;
  END;
  RAISE NOTICE 'OK: replay element';

  -- binding_present: en aktiv binding (draft eller published) afvises; kun en tilbagetrukket lykkes
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('bdd'),v_els->pg_temp.el('bdd'),'RECORD_PERSONA_BINDING_PRESENT');
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('bdp'),v_els->pg_temp.el('bdp'),'RECORD_PERSONA_BINDING_PRESENT');
  PERFORM pg_temp.rp_apply(v_src,v_batch,pg_temp.el('bdw'),v_els->pg_temp.el('bdw'));
  RAISE NOTICE 'OK: binding_present (draft, published afvist; withdrawn lykkes)';

  -- mention_drift og helpost
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('md'),v_els->pg_temp.el('md'),'RECORD_PERSONA_MENTION_DRIFT');  -- forkert tekst-hash
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('mi'),v_els->pg_temp.el('mi'),'RECORD_PERSONA_MENTION_DRIFT');  -- forkert mention-id
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('mm'),v_els->pg_temp.el('mm'),'RECORD_PERSONA_MENTION_DRIFT');  -- to mentions
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('am'),v_els->pg_temp.el('am'),'RECORD_HELPOST_AMBIGUOUS');
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('out'),v_els->pg_temp.el('out'),'RECORD_HELPOST_SUBOCCURRENCE_OUTSIDE');
  RAISE NOTICE 'OK: mention_drift, helpost_ambiguous';

  -- subjektet: levende, ingen external id i kilden (men én i en anden), findes ikke
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('sl'),v_els->pg_temp.el('sl'),'RECORD_PERSONA_SUBJECT_INVALID');
  IF (SELECT count(*) FROM public.person_external_id WHERE person_id=-631011 AND source_id=-6319)<>1
     OR EXISTS (SELECT 1 FROM public.person_external_id WHERE person_id=-631011 AND source_id=-6310) THEN
    RAISE EXCEPTION 'RECORD_PERSONA_TEST_SE_FIXTURE'; END IF;
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('se'),v_els->pg_temp.el('se'),'RECORD_PERSONA_SUBJECT_INVALID');
  RAISE NOTICE 'OK: subject_levende, subject_no_external_id';

  -- persona_exists
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('ex'),v_els->pg_temp.el('ex'),'RECORD_PERSONA_EXISTS');
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('ex2'),v_els->pg_temp.el('ex2'),'RECORD_PERSONA_EXISTS');
  RAISE NOTICE 'OK: persona_exists';

  -- payload_invalid
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('pi'),v_els->pg_temp.el('pi'),'RECORD_PERSONA_PAYLOAD_INVALID');   -- mangler sheet_sha256
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('pi2'),v_els->pg_temp.el('pi2'),'RECORD_PERSONA_PAYLOAD_INVALID'); -- nøgle passer ikke til posten
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('pi3'),v_els->pg_temp.el('pi3'),'RECORD_PERSONA_PAYLOAD_INVALID'); -- forkert prefix
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('pi4'),v_els->pg_temp.el('pi4'),'RECORD_PERSONA_PAYLOAD_INVALID'); -- ekstra nøgle
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('pi5'),v_els->pg_temp.el('pi5'),'RECORD_PERSONA_PAYLOAD_INVALID'); -- sheet_sha256 ikke hex
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('pi6'),v_els->pg_temp.el('pi6'),'RECORD_PERSONA_PAYLOAD_INVALID'); -- sheet_line 0
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('pi7'),v_els->pg_temp.el('pi7'),'RECORD_PERSONA_PAYLOAD_INVALID'); -- sheet_line som tekst
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('pi8'),v_els->pg_temp.el('pi8'),'RECORD_PERSONA_PAYLOAD_INVALID'); -- publication-personaens binding_id
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('pi9'),v_els->pg_temp.el('pi9'),'RECORD_PERSONA_PAYLOAD_INVALID'); -- anden kilde
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('rm'),v_els->pg_temp.el('rm'),'RECORD_PERSONA_RECORD_MISSING');
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('hp'),v_els->pg_temp.el('md'),'REIMPORT_WRITER_ELEMENT_NOT_AUTHORIZED'); -- payload ≠ autoriseret
  -- en profil uden persona_key_prefix kan ikke skrive personas, selv med en ellers korrekt payload
  v_batch_n:=pg_temp.rp_begin(v_src,'fixture-pub-n','np',jsonb_build_object(pg_temp.el('np'),pg_temp.rp_payload(v_src,v_np)));
  PERFORM pg_temp.expect_apply(v_src,v_batch_n,pg_temp.el('np'),pg_temp.rp_payload(v_src,v_np),'RECORD_PERSONA_PAYLOAD_INVALID');
  RAISE NOTICE 'OK: payload_invalid, record_missing, authorization';

  -- ingen af afvisningerne har skrevet noget: hp og bdw er de eneste hændelser og personas med nøgleprefixet
  IF (SELECT count(*) FROM private.reimport_event WHERE batch_id=v_batch)<>2
     OR (SELECT count(*) FROM private.source_persona WHERE source_id=-6310 AND persona_key LIKE '1939:%' AND persona_key<>'1939:ex2')<>2 THEN
    RAISE EXCEPTION 'RECORD_PERSONA_TEST_REJECTIONS_WROTE'; END IF;

  -- rettigheder
  IF has_function_privilege('anon','public.red_apply_reimport_record_persona(uuid,text,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_apply_reimport_record_persona(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('service_role','public.red_apply_reimport_record_persona(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.write_record_persona(uuid,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'RECORD_PERSONA_TEST_PRIVILEGES'; END IF;

  -- not_awaiting_control: personaen venter ikke på publiceringskontrollen og kan afgøres fra kortarket
  IF private.persona_awaiting_control(v_persona) THEN RAISE EXCEPTION 'RECORD_PERSONA_TEST_AWAITING_CONTROL'; END IF;
  PERFORM set_config('request.jwt.claim.sub',v_src->>'actor',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_afgoer_source_persona(v_persona,0,'same',-631001,'kortark linje 1',
    jsonb_build_object('basis','human_sheet','sheet_sha256',v_sheet,'rows_sha256',repeat('b',64),'line',1));
  RESET ROLE;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF (SELECT canonical_person_id FROM private.source_persona_identity WHERE source_persona_id=v_persona AND decision_status='accepted')
     IS DISTINCT FROM -631001 THEN
    RAISE EXCEPTION 'RECORD_PERSONA_TEST_IDENTITY_DECISION'; END IF;
  RAISE NOTICE 'OK: not_awaiting_control';
END $rp$;

-- subject_missing: payloadens person findes ikke (helposten og alt andet er i orden).
DO $missing$
DECLARE v_src jsonb:=pg_temp.pp_source(-6312,'11000000-0000-0000-0000-0000000c0723'); v_fx jsonb; v_payload jsonb; v_batch uuid;
BEGIN
  v_fx:=pg_temp.rp_post(v_src,'sx',-631201);
  v_payload:=pg_temp.rp_payload(v_src,v_fx)||jsonb_build_object('person_id',-631299);
  v_batch:=pg_temp.rp_begin(v_src,'fixture-pub-a','missing',jsonb_build_object(pg_temp.el('sx'),v_payload));
  PERFORM pg_temp.expect_apply(v_src,v_batch,pg_temp.el('sx'),v_payload,'RECORD_PERSONA_SUBJECT_INVALID');
  RAISE NOTICE 'OK: subject_missing';
END $missing$;

-- full_chain: authorize → begin → apply → finalize med to elementer, og replay af samme manifest.
DO $chain$
DECLARE
  v_src jsonb:=pg_temp.pp_source(-6311,'11000000-0000-0000-0000-0000000c0722');
  v_a jsonb; v_b jsonb; v_els jsonb; v_batch uuid; v_again uuid; v_final jsonb;
BEGIN
  v_a:=pg_temp.rp_post(v_src,'ca',-631101); v_b:=pg_temp.rp_post(v_src,'cb',-631102,'{"subs":2}');
  v_els:=jsonb_build_object(pg_temp.el('ca'),pg_temp.rp_payload(v_src,v_a),pg_temp.el('cb'),pg_temp.rp_payload(v_src,v_b));
  v_batch:=pg_temp.rp_begin(v_src,'fixture-pub-a','chain',v_els);
  PERFORM pg_temp.rp_apply(v_src,v_batch,pg_temp.el('ca'),v_els->pg_temp.el('ca'));
  PERFORM pg_temp.rp_apply(v_src,v_batch,pg_temp.el('cb'),v_els->pg_temp.el('cb'));
  PERFORM set_config('request.jwt.claim.sub',v_src->>'actor',true); PERFORM set_config('role','authenticated',true);
  v_final:=public.red_finalize_reimport(v_batch);
  RESET role;
  IF v_final->>'status'<>'finalized' OR (v_final->'counts'->>'record_personas')::int<>2
     OR (SELECT observed_counts->>'record_personas' FROM private.reimport_batch WHERE id=v_batch)<>'2' THEN
    RAISE EXCEPTION 'RECORD_PERSONA_TEST_FINALIZE: %',v_final; END IF;
  -- efter finalize giver samme manifest og preview (ny autorisation) den eksisterende batch igen (already_applied)
  v_again:=pg_temp.rp_begin(v_src,'fixture-pub-a','chain',v_els);
  IF v_again<>v_batch THEN RAISE EXCEPTION 'RECORD_PERSONA_TEST_REPLAY_AFTER_FINALIZE'; END IF;
  IF (SELECT count(*) FROM private.source_persona WHERE source_id=-6311)<>2 THEN
    RAISE EXCEPTION 'RECORD_PERSONA_TEST_CHAIN_PERSONAS'; END IF;
  RAISE NOTICE 'OK: full_chain';
END $chain$;

ROLLBACK;

-- Writeren kræver READ COMMITTED (eksistens- og bindingskontrollerne skal læse efter låsene). SET TRANSACTION skal være
-- transaktionens første sætning, så testen står i egne transaktioner; kontrollen står først i writeren.
BEGIN;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
DO $iso$
DECLARE v_res text;
BEGIN
  BEGIN PERFORM private.write_record_persona(gen_random_uuid(),'record-persona:x','{}'::jsonb); v_res:='OK';
  EXCEPTION WHEN OTHERS THEN v_res:=SQLERRM; END;
  IF v_res IS DISTINCT FROM 'RECORD_PERSONA_ISOLATION' THEN
    RAISE EXCEPTION 'RECORD_PERSONA_TEST_ISOLATION: repeatable read gav %',v_res; END IF;
  RAISE NOTICE 'OK: REPEATABLE READ afvises';
END $iso$;
ROLLBACK;
BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
DO $iso$
DECLARE v_res text;
BEGIN
  BEGIN PERFORM public.red_apply_reimport_record_persona(gen_random_uuid(),'record-persona:x','{}'::jsonb); v_res:='OK';
  EXCEPTION WHEN OTHERS THEN v_res:=SQLERRM; END;
  IF v_res IS DISTINCT FROM 'RECORD_PERSONA_ISOLATION' THEN
    RAISE EXCEPTION 'RECORD_PERSONA_TEST_ISOLATION: serializable gav %',v_res; END IF;
  RAISE NOTICE 'OK: SERIALIZABLE afvises';
END $iso$;
ROLLBACK;
