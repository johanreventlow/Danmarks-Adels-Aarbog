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
    pg_temp.el('pi9'),pg_temp.rp_payload(v_src,v_pi)||jsonb_build_object('source_record_key','pi9','persona_key','1939:pi9','source_id',-6319),
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

-- $to_tekster$ (bred spærring): en person med en tilbagetrukket legacy-tekst og en record-post i samme kilde. Når
-- personen har en record-binding i kilden (i enhver status), afviser fortrydelsen af legacy_withdrawn med
-- NARRATIVE_LEGACY_RECORD_BINDING_EXISTS, og historikken viser samme grund; ellers ville to tekster for kilden kunne
-- blive synlige. Tre forløb: (a) kladde → publicér, (b) kladde → kassér, (c) publicér → tilbagetræk. Kontrol: uden
-- record-binding kan legacy stadig fortrydes.
\i tests/sql/fixtures/kalder-matrix.sql

-- En person med legacy-tekst (grandfathered, derefter tilbagetrukket gennem RPC'en) og en record-post med persona,
-- identitet og placement, så redaktøren kan skrive en kladde. Returnerer nøglerne.
CREATE FUNCTION pg_temp.tt_person(p_src jsonb, p_key text, p_person bigint, p_batch_fx jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_source bigint:=(p_src->>'source')::bigint; v_narr bigint; v_ref uuid:=gen_random_uuid(); v_state jsonb; v_sha text;
  v_res jsonb; v_header uuid; v_rp uuid:=gen_random_uuid(); v_pp uuid:=gen_random_uuid(); v_persona uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.change_set) THEN
    INSERT INTO public.change_set(actor_navn,actor_rolle,operation,summary,subjekt_synlighed)
    VALUES ('fixture','system','fixture','fixture','offentlig');
  END IF;
  INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst,privat)
    VALUES ('person',p_person,v_source,'9','Legacy tekst '||p_key,false) RETURNING id INTO v_narr;
  v_state:=private.narrative_legacy_candidate_publication_state(v_narr,v_source,v_ref);
  v_sha:=encode(extensions.digest(v_state::text,'sha256'),'hex');
  INSERT INTO private.narrative_legacy_publication(legacy_publication_ref,narrative_id,source_id,baseline_state,baseline_sha256,status)
    VALUES (v_ref,v_narr,v_source,v_state,v_sha,'grandfathered_publication');
  INSERT INTO private.narrative_publication_event(change_set_id,stream_ref,stream_version,event_type,narrative_id,source_id,
    legacy_publication_ref,decision_basis,before_state,after_state,before_state_sha256,after_state_sha256,decided_by_name)
  VALUES ((SELECT max(id) FROM public.change_set),v_ref,1,'baseline',v_narr,v_source,v_ref,'fixture',v_state,v_state,v_sha,v_sha,'fixture');
  UPDATE private.narrative_legacy_publication SET latest_event_id=(SELECT id FROM private.narrative_publication_event WHERE stream_ref=v_ref)
   WHERE legacy_publication_ref=v_ref;
  v_sha:=private.narrative_legacy_state(v_ref,false)->>'state_sha256';
  PERFORM set_config('request.jwt.claim.sub',p_src->>'actor',true);
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  v_res:=public.red_tilbagetraek_legacy_narrative(v_ref,v_sha,'to tekster');
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  IF p_batch_fx IS NOT NULL THEN
    -- identitet fra kortarket og placement som i ceremonien (lineage-skema pr. kilde)
    v_persona:=private.content_uuid('source-persona',jsonb_build_object('source_id',v_source,'persona_key','1939:'||p_key));
    SET LOCAL ROLE authenticated;
    PERFORM public.red_afgoer_source_persona(v_persona,0,'same',p_person,'kortark',
      jsonb_build_object('basis','human_sheet','sheet_sha256',repeat('c',64),'rows_sha256',repeat('d',64),'line',1));
    RESET ROLE;
    IF NOT EXISTS (SELECT 1 FROM public.lineage_scheme WHERE id=v_source) THEN
      INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug) VALUES (v_source,'tt slægt','tt slægt','tt-slaegt'||abs(v_source));
      INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label) VALUES (v_source,v_source,v_source,'stamtavle','tt scheme');
      INSERT INTO public.lineage_scheme_entry(id,scheme_id,slaegt_id,code,label,sort_order) VALUES (v_source,v_source,v_source,'A','Linje A',1);
    END IF;
    INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
      verbatim_text,quality_status,extraction_method,extraction_run_id)
      VALUES ((p_batch_fx->>'occ')::uuid,'header',1,1,100,104,'Fixt','clear','fixture',(p_src->>'run')::uuid) RETURNING id INTO v_header;
    INSERT INTO private.source_record_placement(id,source_record_id,scheme_entry_id,header_observation_id,initial_status)
      VALUES (v_rp,(p_batch_fx->>'record')::uuid,v_source,v_header,'accepted');
    INSERT INTO private.source_record_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
      VALUES (v_rp,1,'accepted','{"basis":"tt fixture"}','migration','fixture');
    INSERT INTO private.source_persona_placement(id,source_persona_id,record_placement_id,placement_role,basis_observation_id,initial_status)
      VALUES (v_pp,v_persona,v_rp,'principal_member',(p_batch_fx->>'observation')::uuid,'accepted');
    INSERT INTO private.source_persona_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
      VALUES (v_pp,1,'accepted','{"basis":"tt fixture"}','migration','fixture');
  END IF;
  RETURN jsonb_build_object('legacy_ref',v_ref,'legacy_event',v_res->>'event_id','legacy_narrative',v_narr);
END $$;

-- Én redaktionshandling på posten (upsert/publish/discard/withdraw) med frisk tilstands-hash.
CREATE FUNCTION pg_temp.tt_act(p_src jsonb, p_action text, p_person bigint, p_key text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_source bigint:=(p_src->>'source')::bigint; v_h text; v_r jsonb;
BEGIN
  v_h:=private.narrative_record_state(p_person,v_source,p_key,false)->>'state_sha256';
  PERFORM set_config('request.jwt.claim.sub',p_src->>'actor',true);
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  v_r:=CASE p_action
    WHEN 'upsert' THEN public.red_upsert_person_narrative_record(p_person,v_source,p_key,'Ny tekst '||p_key,false,v_h)
    WHEN 'publish' THEN public.red_publicer_person_narrative_record(p_person,v_source,p_key,v_h)
    WHEN 'discard' THEN public.red_kasser_person_narrative_record(p_person,v_source,p_key,v_h)
    WHEN 'withdraw' THEN public.red_tilbagetraek_person_narrative_record(p_person,v_source,p_key,v_h) END;
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  RETURN v_r;
EXCEPTION WHEN OTHERS THEN RESET ROLE; RAISE;
END $$;

-- Fortryd legacy-hændelsen; NULL = lykkedes, ellers fejlteksten.
CREATE FUNCTION pg_temp.tt_reverse_legacy(p_src jsonb, p_fx jsonb) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_h text:=private.narrative_legacy_state((p_fx->>'legacy_ref')::uuid,false)->>'state_sha256';
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_src->>'actor',true);
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_fortryd_person_narrative_publication_event((p_fx->>'legacy_event')::uuid,v_h);
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN RESET ROLE; RETURN SQLERRM;
END $$;

-- Antal tekster for personen i kilden som gæst (anon uden uid) i v1 og v2, og historikkens grund for legacy-hændelsen.
CREATE FUNCTION pg_temp.tt_check(p_src jsonb, p_person bigint, p_fx jsonb, p_texts int, p_reason text, p_label text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_v1 int; v_v2 int; v_hist record;
BEGIN
  v_v1:=pg_temp.km_antal('gaest',format('SELECT 1 FROM public.public_person_bio_source_versions(ARRAY[%s]::bigint[])',p_person));
  v_v2:=pg_temp.km_antal('gaest',format('SELECT 1 FROM public.public_person_bio_source_versions_v2(ARRAY[%s]::bigint[]) r WHERE r.source_id=%s',
                                        p_person,p_src->>'source'));
  PERFORM set_config('request.jwt.claim.sub',p_src->>'actor',true);
  SELECT h.can_reverse,h.blocking_reason INTO STRICT v_hist FROM public.red_person_narrative_publication_history(p_person) h
   WHERE h.event_id=(p_fx->>'legacy_event')::uuid;
  IF v_v1<>p_texts OR v_v2<>p_texts OR v_hist.blocking_reason IS DISTINCT FROM p_reason
     OR v_hist.can_reverse IS DISTINCT FROM (p_reason IS NULL) THEN
    RAISE EXCEPTION 'TO_TEKSTER_TEST_FAILED: % (v1 %, v2 %, forventet %; historik % %)',p_label,v_v1,v_v2,p_texts,v_hist.can_reverse,v_hist.blocking_reason;
  END IF;
END $$;

DO $to_tekster$
DECLARE
  v_src jsonb:=pg_temp.pp_source(-6313,'11000000-0000-0000-0000-0000000c0724');
  v_a jsonb; v_b jsonb; v_c jsonb; v_k jsonb; v_els jsonb; v_batch uuid; fa jsonb; fb jsonb; fc jsonb; fk jsonb; v_err text;
  v_block text:='NARRATIVE_LEGACY_RECORD_BINDING_EXISTS';
BEGIN
  PERFORM pg_temp.km_kaldere();
  v_a:=pg_temp.rp_post(v_src,'ta',-631301); v_b:=pg_temp.rp_post(v_src,'tb',-631302); v_c:=pg_temp.rp_post(v_src,'tc',-631303);
  v_k:=pg_temp.rp_post(v_src,'tk',-631304);
  v_els:=jsonb_build_object(pg_temp.el('ta'),pg_temp.rp_payload(v_src,v_a),pg_temp.el('tb'),pg_temp.rp_payload(v_src,v_b),
                            pg_temp.el('tc'),pg_temp.rp_payload(v_src,v_c));
  v_batch:=pg_temp.rp_begin(v_src,'fixture-pub-a','to-tekster',v_els);
  PERFORM pg_temp.rp_apply(v_src,v_batch,pg_temp.el('ta'),v_els->pg_temp.el('ta'));
  PERFORM pg_temp.rp_apply(v_src,v_batch,pg_temp.el('tb'),v_els->pg_temp.el('tb'));
  PERFORM pg_temp.rp_apply(v_src,v_batch,pg_temp.el('tc'),v_els->pg_temp.el('tc'));
  fa:=pg_temp.tt_person(v_src,'ta',-631301,v_a); fb:=pg_temp.tt_person(v_src,'tb',-631302,v_b);
  fc:=pg_temp.tt_person(v_src,'tc',-631303,v_c); fk:=pg_temp.tt_person(v_src,'tk',-631304,NULL);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  -- udgangspunkt: legacy er tilbagetrukket og kan fortrydes; ingen tekst for kilden
  PERFORM pg_temp.tt_check(v_src,-631301,fa,0,NULL,'(a) før');

  -- (a) kladde → publicér → fortryd legacy
  PERFORM pg_temp.tt_act(v_src,'upsert',-631301,'ta');
  PERFORM pg_temp.tt_check(v_src,-631301,fa,0,v_block,'(a) kladde');
  PERFORM pg_temp.tt_act(v_src,'publish',-631301,'ta');
  v_err:=pg_temp.tt_reverse_legacy(v_src,fa);
  IF v_err IS NULL OR v_err NOT LIKE v_block||'%' THEN RAISE EXCEPTION 'TO_TEKSTER_TEST_FAILED: (a) fortrydelse gav %',v_err; END IF;
  PERFORM pg_temp.tt_check(v_src,-631301,fa,1,v_block,'(a) publiceret');

  -- (b) kladde → kassér → fortryd legacy (den kasserede binding beholder sin række)
  PERFORM pg_temp.tt_act(v_src,'upsert',-631302,'tb');
  PERFORM pg_temp.tt_act(v_src,'discard',-631302,'tb');
  IF NOT EXISTS (SELECT 1 FROM private.narrative_record_publication b WHERE b.source_record_id=(v_b->>'record')::uuid AND b.status='withdrawn') THEN
    RAISE EXCEPTION 'TO_TEKSTER_TEST_FAILED: (b) kasseret binding uden række'; END IF;
  v_err:=pg_temp.tt_reverse_legacy(v_src,fb);
  IF v_err IS NULL OR v_err NOT LIKE v_block||'%' THEN RAISE EXCEPTION 'TO_TEKSTER_TEST_FAILED: (b) fortrydelse gav %',v_err; END IF;
  PERFORM pg_temp.tt_check(v_src,-631302,fb,0,v_block,'(b) kasseret');

  -- (c) kladde → publicér → tilbagetræk → fortryd legacy
  PERFORM pg_temp.tt_act(v_src,'upsert',-631303,'tc');
  PERFORM pg_temp.tt_act(v_src,'publish',-631303,'tc');
  PERFORM pg_temp.tt_act(v_src,'withdraw',-631303,'tc');
  v_err:=pg_temp.tt_reverse_legacy(v_src,fc);
  IF v_err IS NULL OR v_err NOT LIKE v_block||'%' THEN RAISE EXCEPTION 'TO_TEKSTER_TEST_FAILED: (c) fortrydelse gav %',v_err; END IF;
  PERFORM pg_temp.tt_check(v_src,-631303,fc,0,v_block,'(c) tilbagetrukket');

  -- kontrol: uden record-binding i kilden kan legacy fortrydes, og legacy-teksten er synlig igen
  PERFORM pg_temp.tt_check(v_src,-631304,fk,0,NULL,'kontrol før');
  v_err:=pg_temp.tt_reverse_legacy(v_src,fk);
  IF v_err IS NOT NULL THEN RAISE EXCEPTION 'TO_TEKSTER_TEST_FAILED: kontrol fortrydelse gav %',v_err; END IF;
  PERFORM pg_temp.tt_check(v_src,-631304,fk,1,'NARRATIVE_PUBLICATION_EVENT_ALREADY_REVERSED','kontrol efter');
  RAISE NOTICE 'OK: to_tekster (a) publiceret, (b) kasseret, (c) tilbagetrukket spærret; kontrol uden binding fortrydes';
END $to_tekster$;

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
