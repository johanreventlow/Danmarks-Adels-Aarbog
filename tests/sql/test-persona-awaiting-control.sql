-- Trin 6b Task 3: personas fra en publication_persona-batch venter på kontrol: skjult i køen og spærret for afgørelse,
-- indtil en finaliseret publication_identity-batch navngiver B-batchen. Kræver kontrakt v2 som test-publication-persona.sql.
-- Alt syntetisk; hændelser indsættes direkte som ejer (funktionen læser kun reimport_event/-batch/source_persona_identity).
\set ON_ERROR_STOP on
\i tests/sql/fixtures/publication-persona.sql
BEGIN;

CREATE FUNCTION pg_temp.el(p_key text) RETURNS text LANGUAGE sql AS $$ SELECT 'publication-persona:'||p_key $$;

CREATE FUNCTION pg_temp.as_editor(p_actor text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN PERFORM set_config('request.jwt.claim.sub',p_actor,true); PERFORM set_config('role','authenticated',true); END $$;

CREATE FUNCTION pg_temp.queue_ids(p_actor text, p_status text) RETURNS uuid[] LANGUAGE plpgsql AS $$
DECLARE v uuid[];
BEGIN
  PERFORM pg_temp.as_editor(p_actor);
  SELECT coalesce(array_agg(q.source_persona_id ORDER BY q.source_persona_id),'{}') INTO v
    FROM public.red_source_persona_queue(p_status,-6310,NULL,100,NULL) q;
  RESET role; RETURN v;
EXCEPTION WHEN OTHERS THEN RESET role; RAISE;
END $$;

CREATE FUNCTION pg_temp.decide(p_actor text, p_persona uuid, p_action text, p_person bigint) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.as_editor(p_actor);
  PERFORM public.red_afgoer_source_persona(p_persona,0,p_action,p_person,'synt note','{}'::jsonb);
  RESET role; RETURN 'OK';
EXCEPTION WHEN OTHERS THEN RESET role; RETURN SQLERRM;
END $$;

DO $t$
DECLARE
  v_src jsonb:=pg_temp.pp_source(-6310,'11000000-0000-0000-0000-00000006b310');
  v_actor text:='11000000-0000-0000-0000-00000006b310';
  v_fx jsonb[]; v_k text[]:=ARRAY['b1','b2','b3','n1'];
  v_pers uuid[]:='{}'; v_p uuid; v_i int; v_bB1 uuid; v_bB2 uuid; v_bB3 uuid; v_cOpen uuid; v_cFin uuid; v_cRev uuid;
  v_ids uuid[]; v_res text; v_cols text;
  v_els jsonb;
  v_baseline uuid[];
BEGIN
  FOR v_i IN 1..4 LOOP
    v_fx[v_i]:=pg_temp.pp_post(v_src,v_k[v_i],-631000-v_i);
    INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES (-6310,'1939:'||v_k[v_i],(v_src->>'run')::uuid) RETURNING id INTO v_p;
    INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_p,(v_fx[v_i]->>'mention')::uuid,'primary',1);
    v_pers:=v_pers||v_p;
  END LOOP;
  -- v_pers[1..3] = B-personas (b1 slippes af en finaliseret C, b2 ligger i en tilbagerullet B-batch, b3 har en C, der ikke er finaliseret), v_pers[4] = n1.
  v_baseline:=pg_temp.queue_ids(v_actor,NULL);   -- INGEN publication_persona-hændelser endnu: alle 4 synlige
  IF cardinality(v_baseline)<>4 THEN RAISE EXCEPTION 'AWAITING_TEST_FAILED: basislinje % ',cardinality(v_baseline); END IF;

  v_bB1:=pg_temp.pp_begin(v_src,'fixture-pub-a','b1',jsonb_build_object(pg_temp.el('b1'),pg_temp.pp_payload(v_src,v_fx[1])));
  v_bB2:=pg_temp.pp_begin(v_src,'fixture-pub-a','b2',jsonb_build_object(pg_temp.el('b2'),pg_temp.pp_payload(v_src,v_fx[2])));
  v_bB3:=pg_temp.pp_begin(v_src,'fixture-pub-a','b3',jsonb_build_object(pg_temp.el('b3'),pg_temp.pp_payload(v_src,v_fx[3])));
  v_cOpen:=pg_temp.pp_begin(v_src,'fixture-pub-b','c-open',jsonb_build_object(pg_temp.el('b3'),pg_temp.pp_payload(v_src,v_fx[3])));
  v_cFin:=pg_temp.pp_begin(v_src,'fixture-pub-b','c-fin',jsonb_build_object(pg_temp.el('b1'),pg_temp.pp_payload(v_src,v_fx[1])));
  v_cRev:=pg_temp.pp_begin(v_src,'fixture-pub-b','c-rev',jsonb_build_object(pg_temp.el('b2'),pg_temp.pp_payload(v_src,v_fx[2])));
  FOR v_i IN 1..3 LOOP
    INSERT INTO private.reimport_event(batch_id,element_id,operation,source_record_key,payload,after_sha256)
      VALUES ((ARRAY[v_bB1,v_bB2,v_bB3])[v_i],'publication-persona:'||v_k[v_i],'publication_persona',v_k[v_i],
              jsonb_build_object('result_receipt',jsonb_build_object('source_persona_id',v_pers[v_i])),repeat('a',64));
  END LOOP;

  -- 1) B-personas (b1,b2,b3) venter; n1 er upåvirket
  IF pg_temp.queue_ids(v_actor,NULL)<>ARRAY[v_pers[4]] OR pg_temp.queue_ids(v_actor,'proposed')<>ARRAY[v_pers[4]] THEN
    RAISE EXCEPTION 'AWAITING_TEST_FAILED: B-personas skal være skjult (NULL og proposed)'; END IF;
  FOR v_i IN 1..3 LOOP
    FOREACH v_res IN ARRAY ARRAY['same','unresolved'] LOOP
      IF pg_temp.decide(v_actor,v_pers[v_i],v_res,CASE WHEN v_res='same' THEN -631004 END)<>'IDENTITY_AWAITING_PUBLICATION_CONTROL' THEN
        RAISE EXCEPTION 'AWAITING_TEST_FAILED: afgørelse % af B-persona % skal afvises',v_res,v_i; END IF;
    END LOOP;
  END LOOP;
  IF EXISTS (SELECT 1 FROM private.source_persona_identity WHERE source_persona_id=ANY(v_pers[1:3])) THEN
    RAISE EXCEPTION 'AWAITING_TEST_FAILED: afvist afgørelse efterlod en identitet'; END IF;

  -- 2) tilbagerullet B-batch tæller ikke (b2)
  UPDATE private.reimport_batch SET status='reversed' WHERE id=v_bB2;
  IF NOT (pg_temp.queue_ids(v_actor,NULL) @> ARRAY[v_pers[2]]) THEN RAISE EXCEPTION 'AWAITING_TEST_FAILED: reversed B-batch skal ikke holde personaen'; END IF;

  -- 3) C-batch der IKKE er finaliseret frigiver ikke: open (b3) og reversed (b2's er irrelevant; test med b3)
  INSERT INTO private.reimport_event(batch_id,element_id,operation,source_record_key,payload,after_sha256)
    VALUES (v_cOpen,'publication-identity:'||v_pers[3],'publication_identity','b3',jsonb_build_object('persona_batch_id',v_bB3),repeat('b',64));
  IF v_pers[3]=ANY(pg_temp.queue_ids(v_actor,NULL)) THEN RAISE EXCEPTION 'AWAITING_TEST_FAILED: åben C-batch må ikke frigive'; END IF;
  UPDATE private.reimport_batch SET status='reversed' WHERE id=v_cOpen;
  IF v_pers[3]=ANY(pg_temp.queue_ids(v_actor,NULL)) THEN RAISE EXCEPTION 'AWAITING_TEST_FAILED: tilbagerullet C-batch må ikke frigive'; END IF;
  -- en C-batch der navngiver en ANDEN B-batch frigiver heller ikke b3
  INSERT INTO private.reimport_event(batch_id,element_id,operation,source_record_key,payload,after_sha256)
    VALUES (v_cRev,'publication-identity:x','publication_identity','b2',jsonb_build_object('persona_batch_id',v_bB2),repeat('c',64));
  UPDATE private.reimport_batch SET status='finalized' WHERE id=v_cRev;
  IF v_pers[3]=ANY(pg_temp.queue_ids(v_actor,NULL)) THEN RAISE EXCEPTION 'AWAITING_TEST_FAILED: C for en anden B-batch må ikke frigive b3'; END IF;

  -- 4) finaliseret C, der navngiver b1's B-batch, frigiver b1: synlig som proposed og kan afgøres
  INSERT INTO private.reimport_event(batch_id,element_id,operation,source_record_key,payload,after_sha256)
    VALUES (v_cFin,'publication-identity:'||v_pers[1],'publication_identity','b1',jsonb_build_object('persona_batch_id',v_bB1),repeat('d',64));
  UPDATE private.reimport_batch SET status='finalized' WHERE id=v_cFin;
  IF NOT (v_pers[1]=ANY(pg_temp.queue_ids(v_actor,'proposed'))) THEN RAISE EXCEPTION 'AWAITING_TEST_FAILED: finaliseret C skal frigive b1 som proposed'; END IF;
  IF v_pers[3]=ANY(pg_temp.queue_ids(v_actor,NULL)) THEN RAISE EXCEPTION 'AWAITING_TEST_FAILED: b3 skal stadig vente'; END IF;
  IF pg_temp.decide(v_actor,v_pers[1],'unresolved',NULL)<>'OK' THEN RAISE EXCEPTION 'AWAITING_TEST_FAILED: frigivet b1 skal kunne afgøres'; END IF;
  UPDATE private.reimport_batch SET status='activated' WHERE id=v_cFin;   -- aktiveret C holder stadig frigivet
  IF v_pers[3]=ANY(pg_temp.queue_ids(v_actor,NULL)) THEN RAISE EXCEPTION 'AWAITING_TEST_FAILED: b3 skal stadig vente efter aktivering af anden C'; END IF;

  -- 5) en 2018-20-lignende persona uden identitet er synlig og kan afgøres; køens orden er stigende id
  IF NOT (v_pers[4]=ANY(pg_temp.queue_ids(v_actor,NULL))) THEN RAISE EXCEPTION 'AWAITING_TEST_FAILED: n1 synlig'; END IF;
  IF pg_temp.decide(v_actor,v_pers[4],'unresolved',NULL)<>'OK' THEN RAISE EXCEPTION 'AWAITING_TEST_FAILED: n1 skal kunne afgøres'; END IF;

  -- 6) funktionsfladen: privat, ingen klientrolle kan kalde den; køens kolonner uændrede
  IF has_function_privilege('authenticated','private.persona_awaiting_control(uuid)','EXECUTE')
     OR has_function_privilege('anon','private.persona_awaiting_control(uuid)','EXECUTE')
     OR has_function_privilege('service_role','private.persona_awaiting_control(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'AWAITING_TEST_FAILED: hjælperen kan kaldes af en klientrolle'; END IF;
  SELECT pg_get_function_result('public.red_source_persona_queue(text,bigint,uuid,integer,text)'::regprocedure) INTO v_cols;
  IF v_cols<>'TABLE(source_persona_id uuid, source_id bigint, persona_key text, decision_status text, version integer, canonical_person_id bigint, mention_count bigint, best_tier text, reason text, mention_role text)' THEN
    RAISE EXCEPTION 'AWAITING_TEST_FAILED: køens kolonner ændret: %',v_cols; END IF;
  RAISE NOTICE 'OK: personas der venter på kontrol (kø og afgørelse)';
END $t$;
ROLLBACK;
