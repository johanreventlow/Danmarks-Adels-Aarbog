-- Trin 6b Task 6: writer-operationen publication_identity (ceremoni C, spec §4.3 pkt. 4-6, §4.3.1).
-- Kræver kontrakt v2 (reimport-writer-v2-bootstrap.sql) som test-publication-persona.sql: B-personas skrives gennem den
-- rigtige writer, kandidatkørslen registreres med red_record_identity_candidates. Alt syntetisk; én transaktion, rulles
-- tilbage. Ingen navne eller posttekst i output.
\set ON_ERROR_STOP on
\i tests/sql/fixtures/publication-identity.sql
BEGIN;

-- Verdenen deles mellem blokkene i en midlertidig tabel.
CREATE TEMP TABLE t6(k text PRIMARY KEY, v jsonb);

-- Én payload i sin egen batch: autoriser, åbn og anvend; 'OK' eller fejlteksten. p_element overstyrer elementid'et.
CREATE FUNCTION pg_temp.pi_try(p_world jsonb, p_tag text, p_payload jsonb, p_element text DEFAULT NULL) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v_el text:=coalesce(p_element,pg_temp.pi_el(p_payload)); v_batch uuid;
BEGIN
  v_batch:=pg_temp.pi_begin(p_world,p_tag,jsonb_build_object(v_el,p_payload));
  PERFORM pg_temp.pi_apply(p_world,v_batch,v_el,p_payload);
  RETURN 'OK';
EXCEPTION WHEN OTHERS THEN RETURN SQLERRM;
END $$;

CREATE FUNCTION pg_temp.expect(p_case text, p_got text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_got IS NULL OR p_got NOT LIKE p_token||'%' THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: % forventede % fik %',p_case,p_token,p_got; END IF;
END $$;

-- 0) Fladen: writeren er privat, wrapperen kun for authenticated.
DO $surface$
BEGIN
  IF to_regprocedure('private.write_publication_identity(uuid,text,jsonb)') IS NULL
     OR to_regprocedure('public.red_apply_reimport_publication_identity(uuid,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: funktioner mangler'; END IF;
  IF has_function_privilege('anon','public.red_apply_reimport_publication_identity(uuid,text,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_apply_reimport_publication_identity(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.write_publication_identity(uuid,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: rettigheder'; END IF;
  RAISE NOTICE 'OK: funktionsfladen';
END $surface$;

-- 1) Verden A: 40 B-personas og én kandidatkørsel (list-tilstand) med de fem udfald.
--    1-22 enig · 23-25 svag (uden årstal) · 26-28 uenig · 29-31 navnefaelle · 32-34 ingen_kandidat · 35-40 svag (reserve)
DO $world$
DECLARE
  w jsonb:=pg_temp.pi_world(-6610,'11000000-0000-0000-0000-00000006b610',40);
  -- en anden B-batch (egen kilde, én persona) til blok 3: A's C må ikke frigive den. Den oprettes før kørslen, fordi
  -- kandidatinputtet rummer alle personer i basen; af samme grund markeres persona 40's person staged her (blok 3).
  v_other jsonb:=pg_temp.pi_world(-6611,'11000000-0000-0000-0000-00000006b611',1);
  v_cfg jsonb:='{"topK":10,"autoCutoff":0.9,"controlMargin":0.05}'; v_c jsonb:='[]'::jsonb; v_i int; v_p uuid; v_own bigint; v_k bigint;
  v_run uuid;
BEGIN
  UPDATE public.person SET staged=true WHERE id=-6610040;
  FOR v_i IN 26..34 LOOP
    INSERT INTO public.person(id,levende,privat,status) VALUES (-6610900-v_i,false,false,'pi');
  END LOOP;
  FOR v_i IN 1..40 LOOP
    v_p:=pg_temp.pi_persona(w,v_i); v_own:=-6610000-v_i; v_k:=-6610900-v_i;
    IF v_i<=22 THEN
      v_c:=v_c||pg_temp.pi_cand(v_p,v_own,1,jsonb_build_array(pg_temp.pi_ms(v_own,0.95,ARRAY['name','birth'])));
    ELSIF v_i BETWEEN 26 AND 28 THEN
      v_c:=v_c||pg_temp.pi_cand(v_p,v_k,1,jsonb_build_array(pg_temp.pi_ms(v_k,0.99,ARRAY['name','birth'])))
              ||pg_temp.pi_cand(v_p,v_own,2,jsonb_build_array(pg_temp.pi_ms(v_own,0.80,ARRAY['name','birth'])));
    ELSIF v_i BETWEEN 29 AND 31 THEN
      v_c:=v_c||pg_temp.pi_cand(v_p,v_k,1,jsonb_build_array(pg_temp.pi_ms(v_k,0.90,ARRAY['name','birth'])))
              ||pg_temp.pi_cand(v_p,v_own,2,jsonb_build_array(pg_temp.pi_ms(v_own,0.90,ARRAY['name','birth'])));
    ELSIF v_i BETWEEN 32 AND 34 THEN
      v_c:=v_c||pg_temp.pi_cand(v_p,v_k,1,jsonb_build_array(pg_temp.pi_ms(v_k,0.50,ARRAY['name'])));
    ELSE
      v_c:=v_c||pg_temp.pi_cand(v_p,v_own,1,jsonb_build_array(pg_temp.pi_ms(v_own,0.95,ARRAY['name'])));
    END IF;
  END LOOP;
  v_run:=pg_temp.pi_run(w,v_cfg,v_c);
  -- udfaldene er som tilsigtet (klassifikatoren fra Task 5)
  FOR v_i IN 1..40 LOOP
    IF private.publication_control_outcome(pg_temp.pi_persona(w,v_i),v_run,-6610000-v_i)->>'outcome' IS DISTINCT FROM
       (CASE WHEN v_i<=22 THEN 'enig' WHEN v_i<=25 THEN 'svag' WHEN v_i<=28 THEN 'uenig' WHEN v_i<=31 THEN 'navnefaelle'
             WHEN v_i<=34 THEN 'ingen_kandidat' ELSE 'svag' END) THEN
      RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: fixture-udfald for %',v_i; END IF;
  END LOOP;
  IF (SELECT count(*) FROM private.publication_control_sample(v_run))<>20 THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: stikprøven er ikke 20'; END IF;
  INSERT INTO t6 VALUES ('w',w),('other',v_other),('run',to_jsonb(v_run)),('cfg',v_cfg),('cands',v_c),
    ('sample',(SELECT jsonb_agg(s) FROM private.publication_control_sample(v_run) s));
  RAISE NOTICE 'OK: verden A (40 B-personas, fem udfald, stikprøve 20 af 22 enige)';
END $world$;

-- 2) Afvisninger: hver i sin egen batch; ingen skriver noget.
DO $reject$
DECLARE
  w jsonb:=(SELECT v FROM t6 WHERE k='w'); v_run uuid:=(SELECT (v#>>'{}')::uuid FROM t6 WHERE k='run');
  v_sample uuid[]:=(SELECT array_agg(x::uuid) FROM t6, jsonb_array_elements_text(v) x WHERE k='sample');
  s_in int; s_out int; v_i int; v_p jsonb; v_batch uuid; v_res text; v_ans text; v_cross jsonb;
BEGIN
  SELECT min(i) INTO s_in FROM generate_series(1,22) i WHERE pg_temp.pi_persona(w,i)=ANY(v_sample);
  SELECT min(i) INTO s_out FROM generate_series(1,22) i WHERE NOT pg_temp.pi_persona(w,i)=ANY(v_sample);
  INSERT INTO t6 VALUES ('s_in',to_jsonb(s_in)),('s_out',to_jsonb(s_out));

  -- payloadens form
  PERFORM pg_temp.expect('ekstra nøgle',pg_temp.pi_try(w,'r-x',pg_temp.pi_payload(w,23,v_run,'svag','S','{"x":1}')),'PUBLICATION_IDENTITY_PAYLOAD_INVALID');
  PERFORM pg_temp.expect('svag uden svar',pg_temp.pi_try(w,'r-sn',pg_temp.pi_payload(w,23,v_run,'svag',NULL)),'PUBLICATION_IDENTITY_PAYLOAD_INVALID');
  PERFORM pg_temp.expect('enig med F',pg_temp.pi_try(w,'r-ef',pg_temp.pi_payload(w,s_in,v_run,'enig','F')),'PUBLICATION_IDENTITY_PAYLOAD_INVALID');
  PERFORM pg_temp.expect('enig med U',pg_temp.pi_try(w,'r-eu',pg_temp.pi_payload(w,s_in,v_run,'enig','U')),'PUBLICATION_IDENTITY_PAYLOAD_INVALID');
  PERFORM pg_temp.expect('arkfelt uden svar',pg_temp.pi_try(w,'r-as',
    pg_temp.pi_payload(w,s_out,v_run,'enig',NULL,jsonb_build_object('sheet_sha256',repeat('a',64)))),'PUBLICATION_IDENTITY_PAYLOAD_INVALID');
  PERFORM pg_temp.expect('svar uden arkfelt',pg_temp.pi_try(w,'r-sa',
    pg_temp.pi_payload(w,23,v_run,'svag','S','{"sheet_line":null}')),'PUBLICATION_IDENTITY_PAYLOAD_INVALID');
  PERFORM pg_temp.expect('hint ved F',pg_temp.pi_try(w,'r-hf',
    pg_temp.pi_payload(w,23,v_run,'svag','F','{"same_as_hint_person_id":-6610926}')),'PUBLICATION_IDENTITY_PAYLOAD_INVALID');
  PERFORM pg_temp.expect('hint = bindingspersonen',pg_temp.pi_try(w,'r-hs',
    pg_temp.pi_payload(w,23,v_run,'svag','S','{"same_as_hint_person_id":-6610023}')),'PUBLICATION_IDENTITY_PAYLOAD_INVALID');
  PERFORM pg_temp.expect('version 1',pg_temp.pi_try(w,'r-v1',
    pg_temp.pi_payload(w,23,v_run,'svag','S','{"expected_identity_version":1}')),'PUBLICATION_IDENTITY_PAYLOAD_INVALID');
  PERFORM pg_temp.expect('elementid',pg_temp.pi_try(w,'r-el',pg_temp.pi_payload(w,23,v_run,'svag','S'),
    'publication-identity:'||pg_temp.pi_persona(w,24)),'PUBLICATION_IDENTITY_PAYLOAD_INVALID');
  PERFORM pg_temp.expect('fremmed B-batch',pg_temp.pi_try(w,'r-pb',
    pg_temp.pi_payload(w,23,v_run,'svag','S',jsonb_build_object('persona_batch_id',gen_random_uuid()))),'PUBLICATION_IDENTITY_PAYLOAD_INVALID');
  PERFORM pg_temp.expect('draft-status',pg_temp.pi_try(w,'r-ds',
    pg_temp.pi_payload(w,23,v_run,'svag','S','{"binding_status":"draft"}')),'PUBLICATION_IDENTITY_PAYLOAD_INVALID');
  PERFORM pg_temp.expect('ukendt udfald',pg_temp.pi_try(w,'r-uu',pg_temp.pi_payload(w,23,v_run,'ukendt','S')),'PUBLICATION_IDENTITY_PAYLOAD_INVALID');
  -- payload ≠ den autoriserede
  v_p:=pg_temp.pi_payload(w,23,v_run,'svag','S');
  v_batch:=pg_temp.pi_begin(w,'r-na',jsonb_build_object(pg_temp.pi_el(v_p),v_p));
  BEGIN PERFORM pg_temp.pi_apply(w,v_batch,pg_temp.pi_el(v_p),v_p||'{"sheet_line":99}'); v_res:='OK';
  EXCEPTION WHEN OTHERS THEN v_res:=SQLERRM; END;
  PERFORM pg_temp.expect('ikke autoriseret',v_res,'REIMPORT_WRITER_ELEMENT_NOT_AUTHORIZED');

  -- kørslen: forkert kandidathash eller ukendt kørsel
  PERFORM pg_temp.expect('kandidathash',pg_temp.pi_try(w,'r-ch',
    pg_temp.pi_payload(w,23,v_run,'svag','S',jsonb_build_object('candidates_sha256',repeat('0',64)))),'PUBLICATION_IDENTITY_RUN_STALE');
  PERFORM pg_temp.expect('ukendt kørsel',pg_temp.pi_try(w,'r-uk',
    pg_temp.pi_payload(w,23,v_run,'svag','S',jsonb_build_object('candidate_run_id',gen_random_uuid()))),'PUBLICATION_IDENTITY_RUN_STALE');

  -- forkert udfald
  PERFORM pg_temp.expect('svag som uenig',pg_temp.pi_try(w,'r-o1',pg_temp.pi_payload(w,23,v_run,'uenig','S')),'PUBLICATION_IDENTITY_OUTCOME_MISMATCH');
  PERFORM pg_temp.expect('enig som svag',pg_temp.pi_try(w,'r-o2',pg_temp.pi_payload(w,s_in,v_run,'svag','S')),'PUBLICATION_IDENTITY_OUTCOME_MISMATCH');
  PERFORM pg_temp.expect('ingen_kandidat som enig',pg_temp.pi_try(w,'r-o3',pg_temp.pi_payload(w,32,v_run,'enig',NULL)),'PUBLICATION_IDENTITY_OUTCOME_MISMATCH');

  -- stikprøven: enig i stikprøven uden S, enig uden for stikprøven med S
  PERFORM pg_temp.expect('stikprøve uden S',pg_temp.pi_try(w,'r-s1',pg_temp.pi_payload(w,s_in,v_run,'enig',NULL)),'PUBLICATION_IDENTITY_SAMPLE_MISMATCH');
  PERFORM pg_temp.expect('ikke-stikprøve med S',pg_temp.pi_try(w,'r-s2',pg_temp.pi_payload(w,s_out,v_run,'enig','S')),'PUBLICATION_IDENTITY_SAMPLE_MISMATCH');

  -- krydsning: persona 23 med binding (og person) 24, for S, F, U; og persona s_in (enig) med binding s_out
  v_cross:=jsonb_build_object('binding_id',pg_temp.pi_post(w,24)->>'binding','person_id',(pg_temp.pi_post(w,24)->>'person')::bigint);
  FOREACH v_ans IN ARRAY ARRAY['S','F','U'] LOOP
    PERFORM pg_temp.expect('krydsning '||v_ans,pg_temp.pi_try(w,'r-k'||v_ans,pg_temp.pi_payload(w,23,v_run,'svag',v_ans,v_cross)),
      'PUBLICATION_IDENTITY_BINDING_DRIFT');
  END LOOP;
  PERFORM pg_temp.expect('krydsning enig',pg_temp.pi_try(w,'r-ke',pg_temp.pi_payload(w,s_in,v_run,'enig','S',
    jsonb_build_object('binding_id',pg_temp.pi_post(w,s_out)->>'binding','person_id',(pg_temp.pi_post(w,s_out)->>'person')::bigint))),
    'PUBLICATION_IDENTITY_BINDING_DRIFT');
  PERFORM pg_temp.expect('anden person',pg_temp.pi_try(w,'r-kp',pg_temp.pi_payload(w,23,v_run,'svag','S',
    jsonb_build_object('person_id',(pg_temp.pi_post(w,24)->>'person')::bigint))),'PUBLICATION_IDENTITY_BINDING_DRIFT');

  -- bindingen trukket tilbage efter manifestet (persona 37)
  v_p:=pg_temp.pi_payload(w,37,v_run,'svag','S');
  v_batch:=pg_temp.pi_begin(w,'r-wd',jsonb_build_object(pg_temp.pi_el(v_p),v_p));
  UPDATE private.narrative_record_publication SET status='withdrawn' WHERE id=(pg_temp.pi_post(w,37)->>'binding')::uuid;
  BEGIN PERFORM pg_temp.pi_apply(w,v_batch,pg_temp.pi_el(v_p),v_p); v_res:='OK'; EXCEPTION WHEN OTHERS THEN v_res:=SQLERRM; END;
  PERFORM pg_temp.expect('tilbagetrukket binding',v_res,'PUBLICATION_IDENTITY_BINDING_DRIFT');

  -- identiteten er allerede version 1 (persona 38: en menneskelig afgørelse direkte i kernen)
  PERFORM set_config('request.jwt.claim.sub',w->'src'->>'actor',true);
  PERFORM private.decide_source_persona_identity(pg_temp.pi_persona(w,38),-6610038,0,'accepted','{"basis":"web_detail","note":"t"}','human');
  PERFORM pg_temp.expect('version 1',pg_temp.pi_try(w,'r-vc',pg_temp.pi_payload(w,38,v_run,'svag','S')),'EVIDENCE_IDENTITY_VERSION_CONFLICT');

  IF EXISTS (SELECT 1 FROM private.reimport_event e JOIN private.reimport_batch b ON b.id=e.batch_id
              WHERE b.source_id=-6610 AND e.operation='publication_identity')
     OR (SELECT count(*) FROM private.source_persona_identity i JOIN private.source_persona sp ON sp.id=i.source_persona_id
          WHERE sp.source_id=-6610)<>1 THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: en afvisning skrev'; END IF;
  RAISE NOTICE 'OK: afvisninger (form, autorisation, kørsel, udfald, stikprøve, krydsning, tilbagetrækning, version)';
END $reject$;

-- 3) Fuld kæde: 34 elementer (hvert udfald med hvert tilladt svar) og finalize; status, oprindelse og evidens pr. svar.
--    Codex 6B-01: C skal omfatte HELE B-batchens kontrolmængde (ikke-staged personas uden identitet fra før C), ellers
--    afviser finalize med PUBLICATION_IDENTITY_SET_MISMATCH og hele C rulles tilbage:
--    3a) de 34 alene (35-37 og 39 mangler) afvises; 3b) hele mængden plus en staged persona (40) afvises, og det gør
--    også en udskiftning med samme antal (39 ud, 40 ind); 3c) hele mængden (1-37 og 39; 38 har en identitet fra blok 2,
--    40 er staged) går igennem, og kun C's personas og den staged frigives: en anden B-batchs persona venter stadig.
DO $chain$
DECLARE
  w jsonb:=(SELECT v FROM t6 WHERE k='w'); v_run uuid:=(SELECT (v#>>'{}')::uuid FROM t6 WHERE k='run');
  v_sample uuid[]:=(SELECT array_agg(x::uuid) FROM t6, jsonb_array_elements_text(v) x WHERE k='sample');
  v_payloads jsonb:='[]'::jsonb; v_rest jsonb:='[]'::jsonb; v_all jsonb; v_p40 jsonb; v_try jsonb; v_i int; v_k int;
  v_ans text; v_out text; v_p jsonb; v_batch uuid; v_final jsonb; v_rc jsonb; v_res text; v_tag text; v_other jsonb;
  v_id private.source_persona_identity%ROWTYPE; v_ev private.reimport_event%ROWTYPE; v_cands_sha text;
  v_state1 jsonb; v_state26 jsonb; v_receipts jsonb:='{}'::jsonb;
BEGIN
  v_other:=(SELECT v FROM t6 WHERE k='other');
  v_state1:=private.narrative_publication_state(-6610001,-6610,'r1');
  v_state26:=private.narrative_publication_state(-6610026,-6610,'r26');
  FOR v_i IN 1..34 LOOP
    v_out:=CASE WHEN v_i<=22 THEN 'enig' WHEN v_i<=25 THEN 'svag' WHEN v_i<=28 THEN 'uenig' WHEN v_i<=31 THEN 'navnefaelle'
                ELSE 'ingen_kandidat' END;
    v_ans:=CASE WHEN v_i<=22 THEN CASE WHEN pg_temp.pi_persona(w,v_i)=ANY(v_sample) THEN 'S' END
                ELSE (ARRAY['S','F','U'])[((v_i-23)%3)+1] END;
    v_p:=pg_temp.pi_payload(w,v_i,v_run,v_out,v_ans,
           CASE WHEN v_i=29 THEN '{"same_as_hint_person_id":-6610929}'::jsonb ELSE '{}'::jsonb END);
    v_payloads:=v_payloads||jsonb_build_array(v_p);
  END LOOP;
  -- resten af kontrolmængden: 35-37 og 39 (svag uden årstal); 37's binding, trukket tilbage i blok 2, genoprettes
  UPDATE private.narrative_record_publication SET status='published' WHERE id=(pg_temp.pi_post(w,37)->>'binding')::uuid;
  FOREACH v_i IN ARRAY ARRAY[35,36,37,39] LOOP
    v_rest:=v_rest||jsonb_build_array(pg_temp.pi_payload(w,v_i,v_run,'svag','S'));
  END LOOP;
  v_all:=v_payloads||v_rest;
  v_p40:=pg_temp.pi_payload(w,40,v_run,'svag','S');

  -- 3a) delvis C (de 34): writeren godtager hvert element, finalize afviser mængden; intet efterlades
  v_batch:=pg_temp.pi_begin(w,'chain-partial',pg_temp.pi_elements(v_payloads));
  BEGIN
    FOR v_k IN 0..jsonb_array_length(v_payloads)-1 LOOP
      v_p:=v_payloads->v_k; PERFORM pg_temp.pi_apply(w,v_batch,pg_temp.pi_el(v_p),v_p);
    END LOOP;
    PERFORM pg_temp.pi_finalize(w,v_batch); v_res:='OK';
  EXCEPTION WHEN OTHERS THEN v_res:=SQLERRM;
  END;
  PERFORM pg_temp.expect('delvis C',v_res,'PUBLICATION_IDENTITY_SET_MISMATCH');
  IF EXISTS (SELECT 1 FROM private.reimport_event WHERE batch_id=v_batch)
     OR (SELECT status FROM private.reimport_batch WHERE id=v_batch)<>'open'
     OR EXISTS (SELECT 1 FROM private.source_persona_identity WHERE source_persona_id=pg_temp.pi_persona(w,1))
     OR NOT private.persona_awaiting_control(pg_temp.pi_persona(w,1))
     OR NOT private.persona_awaiting_control(pg_temp.pi_persona(w,35)) THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: delvis C efterlod skrivning eller frigivelse'; END IF;

  -- 3b) persona 40's person er staged (blok 1; disposition, ikke element): med 40 ekstra, og med 40 i stedet for 39
  FOREACH v_tag IN ARRAY ARRAY['chain-extra','chain-swap'] LOOP
    v_try:=CASE WHEN v_tag='chain-extra' THEN v_all||jsonb_build_array(v_p40)
                ELSE (SELECT jsonb_agg(x) FROM jsonb_array_elements(v_all) x WHERE x->>'source_persona_id'<>pg_temp.pi_persona(w,39)::text)
                     ||jsonb_build_array(v_p40) END;
    IF v_tag='chain-swap' AND jsonb_array_length(v_try)<>jsonb_array_length(v_all) THEN
      RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: udskiftningen har ikke samme antal'; END IF;
    v_batch:=pg_temp.pi_begin(w,v_tag,pg_temp.pi_elements(v_try));
    BEGIN
      FOR v_k IN 0..jsonb_array_length(v_try)-1 LOOP
        v_p:=v_try->v_k; PERFORM pg_temp.pi_apply(w,v_batch,pg_temp.pi_el(v_p),v_p);
      END LOOP;
      PERFORM pg_temp.pi_finalize(w,v_batch); v_res:='OK';
    EXCEPTION WHEN OTHERS THEN v_res:=SQLERRM;
    END;
    PERFORM pg_temp.expect(v_tag,v_res,'PUBLICATION_IDENTITY_SET_MISMATCH');
    IF EXISTS (SELECT 1 FROM private.reimport_event WHERE batch_id=v_batch)
       OR EXISTS (SELECT 1 FROM private.source_persona_identity WHERE source_persona_id=pg_temp.pi_persona(w,40)) THEN
      RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: % efterlod skrivning',v_tag; END IF;
  END LOOP;

  -- 3c) hele kontrolmængden
  v_batch:=pg_temp.pi_begin(w,'chain',pg_temp.pi_elements(v_all));
  FOR v_k IN 0..jsonb_array_length(v_all)-1 LOOP
    v_p:=v_all->v_k;
    v_rc:=pg_temp.pi_apply(w,v_batch,pg_temp.pi_el(v_p),v_p);
    IF v_k<34 THEN v_receipts:=v_receipts||jsonb_build_object((v_k+1)::text,v_rc); END IF;
  END LOOP;
  -- C-batchen er åben: den staged B-persona uden for C (40) venter stadig på kontrol
  IF NOT private.persona_awaiting_control(pg_temp.pi_persona(w,40)) THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: venter ikke før finalize'; END IF;
  v_final:=pg_temp.pi_finalize(w,v_batch);
  IF v_final->>'status'<>'finalized' OR (v_final->'counts'->>'publication_identities')::int<>38
     OR (SELECT observed_counts->>'publication_identities' FROM private.reimport_batch WHERE id=v_batch)<>'38' THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: finalize %',v_final; END IF;

  SELECT candidates_sha256 INTO v_cands_sha FROM private.source_persona_identity_candidate_run WHERE id=v_run;
  FOR v_i IN 1..34 LOOP
    v_p:=v_payloads->(v_i-1); v_ans:=v_p->>'answer'; v_out:=v_p->>'outcome'; v_rc:=v_receipts->v_i::text;
    SELECT * INTO v_id FROM private.source_persona_identity WHERE source_persona_id=pg_temp.pi_persona(w,v_i);
    SELECT * INTO v_ev FROM private.reimport_event WHERE batch_id=v_batch AND element_id=pg_temp.pi_el(v_p);
    IF v_id.version<>1 OR v_rc->>'identity_version'<>'1' OR v_ev.payload->'result_receipt'<>v_rc
       OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_rc) k)<>ARRAY['decision_status','identity_version','origin']
       OR v_ev.payload->>'persona_batch_id'<>w->>'b_batch' OR v_ev.operation<>'publication_identity'
       OR v_ev.source_record_key<>'r'||v_i OR v_id.evidence->>'binding_id'<>v_p->>'binding_id'
       OR v_id.evidence->>'candidate_run_id'<>v_run::text OR v_id.evidence->>'candidates_sha256'<>v_cands_sha
       OR v_id.evidence->>'outcome'<>v_out OR v_rc->>'decision_status'<>v_id.decision_status THEN
      RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: kvittering/evidens for % (%)',v_i,v_rc; END IF;
    IF v_out='enig' THEN
      -- oprindelse publication_binding: accepted på bindingspersonen, autoritet, ingen basis; arkfelterne kun i stikprøven
      IF v_rc->>'origin'<>'publication_binding' OR v_id.decision_status<>'accepted' OR v_id.canonical_person_id<>-6610000-v_i
         OR v_id.evidence->>'authority'<>'narrative_record_publication' OR v_id.evidence ? 'basis'
         OR v_ev.canonical_person_id<>-6610000-v_i
         OR (v_ans IS NULL AND (v_id.evidence ? 'sheet_sha256' OR v_id.evidence ? 'line'))
         OR (v_ans='S' AND (v_id.evidence->>'sheet_sha256'<>repeat('a',64) OR v_id.evidence->>'rows_sha256'<>repeat('b',64)
                            OR (v_id.evidence->>'line')::int<>v_i OR v_id.evidence->>'answer'<>'S')) THEN
        RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: enig % (%)',v_i,v_id.evidence; END IF;
    ELSE
      -- oprindelse human, basis human_sheet med arkets hash, rækkefilens hash og linjen
      IF v_rc->>'origin'<>'human' OR v_id.evidence->>'basis'<>'human_sheet' OR v_id.evidence ? 'authority'
         OR v_id.evidence->>'sheet_sha256'<>repeat('a',64) OR v_id.evidence->>'rows_sha256'<>repeat('b',64)
         OR (v_id.evidence->>'line')::int<>v_i OR v_id.evidence->>'answer'<>v_ans
         OR (v_ans='S' AND (v_id.decision_status<>'accepted' OR v_id.canonical_person_id<>-6610000-v_i OR v_id.evidence ? 'reason'
                            OR v_ev.canonical_person_id<>-6610000-v_i))
         OR (v_ans='F' AND (v_id.decision_status<>'unresolved' OR v_id.canonical_person_id IS NOT NULL
                            OR v_id.evidence->>'reason' IS DISTINCT FROM 'publication_binding_disputed' OR v_ev.canonical_person_id IS NOT NULL))
         OR (v_ans='U' AND (v_id.decision_status<>'unresolved' OR v_id.canonical_person_id IS NOT NULL
                            OR v_id.evidence->>'reason' IS DISTINCT FROM 'unknown'))
         OR (v_i=29 AND (v_id.evidence->>'same_as_hint_person_id')::bigint IS DISTINCT FROM -6610929)
         OR (v_i<>29 AND v_id.evidence ? 'same_as_hint_person_id') THEN
        RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: % % % (%)',v_out,v_ans,v_i,v_id.evidence; END IF;
    END IF;
  END LOOP;
  -- tal: 22 publication_binding (20 med arkfelter), 16 human (12 fra 23-34 med 4 S, 4 F, 4 U, og 4 S fra 35-37 og 39)
  IF (SELECT count(*) FROM private.reimport_event WHERE batch_id=v_batch AND payload->'result_receipt'->>'origin'='publication_binding')<>22
     OR (SELECT count(*) FROM private.reimport_event WHERE batch_id=v_batch AND payload->'result_receipt'->>'origin'='publication_binding'
          AND payload->>'answer'='S')<>20
     OR (SELECT count(*) FROM private.reimport_event WHERE batch_id=v_batch AND payload->'result_receipt'->>'origin'='human')<>16 THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: tal pr. oprindelse'; END IF;
  -- efter finalize venter ingen af B's personas: C's 38 har identitet, 38 havde en fra før, og den staged (40) frigives uden
  -- identitet (synlig som proposed); en anden B-batchs persona frigives ikke af denne C
  IF EXISTS (SELECT 1 FROM jsonb_array_elements_text(w->'personas') p WHERE private.persona_awaiting_control(p::uuid)) THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: B-personas venter efter C'; END IF;
  IF EXISTS (SELECT 1 FROM private.source_persona_identity WHERE source_persona_id=pg_temp.pi_persona(w,40))
     OR (SELECT count(*) FROM private.source_persona_identity i
          WHERE i.source_persona_id IN (SELECT x::uuid FROM jsonb_array_elements_text(w->'personas') x))<>39
     OR NOT private.persona_awaiting_control(pg_temp.pi_persona(v_other,1)) THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: frigivelse ud over C og staged'; END IF;
  -- publiceringstilstanden er byte-ens
  IF private.narrative_publication_state(-6610001,-6610,'r1')::text<>v_state1::text
     OR private.narrative_publication_state(-6610026,-6610,'r26')::text<>v_state26::text THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: narrative_publication_state ændret'; END IF;
  -- replay: samme manifest efter finalize giver den eksisterende batch (ingen nye hændelser)
  IF pg_temp.pi_begin(w,'chain',pg_temp.pi_elements(v_all))<>v_batch
     OR (SELECT count(*) FROM private.reimport_event WHERE batch_id=v_batch)<>38 THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: replay efter finalize'; END IF;
  -- den udskudte commit-vagt (Controller efter 6B-01): kæden er finaliseret, så den består nu; 3a/3b's hændelser er rullet
  -- tilbage med deres undertransaktioner og tæller ikke
  SET CONSTRAINTS private.trg_reimport_event_publication_identity_finalized IMMEDIATE;
  SET CONSTRAINTS private.trg_reimport_event_publication_identity_finalized DEFERRED;
  INSERT INTO t6 VALUES ('chain_batch',to_jsonb(v_batch));
  RAISE NOTICE 'OK: kontrolmængden (delvis, ekstra staged og udskiftet afvist; fuld kæde 38 elementer, fem udfald × tilladte svar, kun C og staged frigives)';
END $chain$;

-- 4) RUN_STALE: en ny kandidatkørsel efter manifestet; og to kørsler i samme batch. Egen verden (2 B-personas), fordi
--    kæden i blok 3 har afgjort hele verden A.
DO $stale$
DECLARE
  w jsonb:=pg_temp.pi_world(-6612,'11000000-0000-0000-0000-00000006b612',2);
  v_cfg jsonb:=(SELECT v FROM t6 WHERE k='cfg'); v_c jsonb; v_run uuid;
  v_p1 jsonb; v_p2 jsonb; v_batch uuid; v_res text; v_run2 uuid; v_run3 uuid; v_run3_pre uuid; v_input_sha text;
BEGIN
  v_c:=jsonb_build_array(
         pg_temp.pi_cand(pg_temp.pi_persona(w,1),-6612001,1,jsonb_build_array(pg_temp.pi_ms(-6612001,0.95,ARRAY['name']))),
         pg_temp.pi_cand(pg_temp.pi_persona(w,2),-6612002,1,jsonb_build_array(pg_temp.pi_ms(-6612002,0.95,ARRAY['name']))));
  v_run:=pg_temp.pi_run(w,v_cfg,v_c);
  -- autoriseret mod kørsel 1; kørsel 2 registreres bagefter (samme input, ny config) → C afviser
  v_p1:=pg_temp.pi_payload(w,1,v_run,'svag','S');
  v_batch:=pg_temp.pi_begin(w,'st-1',jsonb_build_object(pg_temp.pi_el(v_p1),v_p1));
  v_run2:=pg_temp.pi_run(w,v_cfg||'{"v":2}',v_c);
  IF v_run2=v_run THEN RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: ingen ny kørsel'; END IF;
  BEGIN PERFORM pg_temp.pi_apply(w,v_batch,pg_temp.pi_el(v_p1),v_p1); v_res:='OK'; EXCEPTION WHEN OTHERS THEN v_res:=SQLERRM; END;
  PERFORM pg_temp.expect('ny kørsel efter manifestet',v_res,'PUBLICATION_IDENTITY_RUN_STALE');

  -- to kørsler i én batch: element 1 mod kørsel 2 (seneste), så registreres kørsel 3, og element 2 mod kørsel 3 afvises,
  -- selv om kørsel 3 nu er den seneste. Kørsel 3's id er et indholds-id og kan beregnes før registreringen.
  SELECT input_sha256 INTO v_input_sha FROM private.source_persona_identity_candidate_run WHERE id=v_run2;
  v_run3_pre:=private.content_uuid('identity-candidate-run',jsonb_build_object('source_id',-6612,'input_sha256',v_input_sha,
    'config_sha256',private.reimport_canonical_json_sha256(v_cfg||'{"v":3}')));
  v_p1:=pg_temp.pi_payload(w,1,v_run2,'svag','S');
  v_p2:=pg_temp.pi_payload(w,2,v_run2,'svag','S')
         ||jsonb_build_object('candidate_run_id',v_run3_pre,'candidates_sha256',private.reimport_canonical_json_sha256(v_c));
  v_batch:=pg_temp.pi_begin(w,'st-2',pg_temp.pi_elements(jsonb_build_array(v_p1,v_p2)));
  PERFORM pg_temp.pi_apply(w,v_batch,pg_temp.pi_el(v_p1),v_p1);
  -- commit-vagten: st-2 er åben med en hændelse; kontrolleres den nu (som ved commit), afvises den
  BEGIN
    SET CONSTRAINTS private.trg_reimport_event_publication_identity_finalized IMMEDIATE;
    v_res:='OK';
  EXCEPTION WHEN OTHERS THEN v_res:=SQLERRM;
  END;
  SET CONSTRAINTS private.trg_reimport_event_publication_identity_finalized DEFERRED;
  PERFORM pg_temp.expect('åben batch ved commit',v_res,'PUBLICATION_IDENTITY_UNFINALIZED');
  v_run3:=pg_temp.pi_run(w,v_cfg||'{"v":3}',v_c);
  IF v_run3<>v_run3_pre THEN RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: kørsel 3''s id'; END IF;
  BEGIN PERFORM pg_temp.pi_apply(w,v_batch,pg_temp.pi_el(v_p2),v_p2); v_res:='OK'; EXCEPTION WHEN OTHERS THEN v_res:=SQLERRM; END;
  PERFORM pg_temp.expect('to kørsler i én batch',v_res,'PUBLICATION_IDENTITY_RUN_STALE');
  -- og finalize af en C-batch afvises, hvis kørslen ikke længere er den seneste: element 2 anvendes mod kørsel 3
  -- (den seneste), derefter registreres kørsel 4, og finalize afviser med RUN_STALE.
  v_p2:=pg_temp.pi_payload(w,2,v_run3,'svag','S');
  v_batch:=pg_temp.pi_begin(w,'st-3',jsonb_build_object(pg_temp.pi_el(v_p2),v_p2));
  PERFORM pg_temp.pi_apply(w,v_batch,pg_temp.pi_el(v_p2),v_p2);
  PERFORM pg_temp.pi_run(w,v_cfg||'{"v":4}',v_c);
  BEGIN PERFORM pg_temp.pi_finalize(w,v_batch); v_res:='OK'; EXCEPTION WHEN OTHERS THEN v_res:=SQLERRM; END;
  PERFORM pg_temp.expect('finalize efter ny kørsel',v_res,'PUBLICATION_IDENTITY_RUN_STALE');
  IF (SELECT status FROM private.reimport_batch WHERE id=v_batch)='finalized' THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: batch finalized trods RUN_STALE'; END IF;
  RAISE NOTICE 'OK: RUN_STALE (ny kørsel efter manifestet; to kørsler i én batch)';
END $stale$;

-- 5) Inputdrift: en proposed person.name-fortolkning ændres efter kandidatkørslen. Alle apply-kald og finalize i én
--    (under)transaktion som runneren: finalize afviser, og intet er skrevet efter tilbagerulningen.
DO $drift$
DECLARE
  w jsonb:=pg_temp.pi_world(-6620,'11000000-0000-0000-0000-00000006b620',3);
  v_cfg jsonb:='{"topK":10,"autoCutoff":0.9,"controlMargin":0.05}'; v_c jsonb; v_run uuid; v_payloads jsonb; v_batch uuid; v_res text;
  v_iid uuid:=gen_random_uuid(); v_i int; v_p jsonb;
BEGIN
  v_c:=jsonb_build_array(
         pg_temp.pi_cand(pg_temp.pi_persona(w,1),-6620001,1,jsonb_build_array(pg_temp.pi_ms(-6620001,0.95,ARRAY['name','birth']))),
         pg_temp.pi_cand(pg_temp.pi_persona(w,2),-6620002,1,jsonb_build_array(pg_temp.pi_ms(-6620002,0.95,ARRAY['name']))),
         pg_temp.pi_cand(pg_temp.pi_persona(w,3),-6620003,1,jsonb_build_array(pg_temp.pi_ms(-6620003,0.95,ARRAY['name']))));
  v_run:=pg_temp.pi_run(w,v_cfg,v_c);
  v_payloads:=jsonb_build_array(pg_temp.pi_payload(w,1,v_run,'enig','S'),pg_temp.pi_payload(w,2,v_run,'svag','S'),
                                pg_temp.pi_payload(w,3,v_run,'svag','F'));
  v_batch:=pg_temp.pi_begin(w,'drift',pg_temp.pi_elements(v_payloads));
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,predicate,value,
    schema_version,derivation_kind,confidence,status,method,extraction_run_id)
  VALUES (v_iid,gen_random_uuid(),1,-6620,pg_temp.pi_persona(w,2),'property','person.name','"Syntetisk ændret"','t','model_inference',0.9,
          'proposed','t',(w->'src'->>'run')::uuid);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_iid,(pg_temp.pi_post(w,2)->>'observation')::uuid,'supporting',1);
  BEGIN
    FOR v_i IN 1..3 LOOP
      v_p:=v_payloads->(v_i-1);
      PERFORM pg_temp.pi_apply(w,v_batch,pg_temp.pi_el(v_p),v_p);
    END LOOP;
    PERFORM pg_temp.pi_finalize(w,v_batch);
    v_res:='OK';
  EXCEPTION WHEN OTHERS THEN v_res:=SQLERRM;
  END;
  PERFORM pg_temp.expect('inputdrift',v_res,'PUBLICATION_IDENTITY_INPUT_DRIFT');
  IF EXISTS (SELECT 1 FROM private.reimport_event WHERE batch_id=v_batch)
     OR EXISTS (SELECT 1 FROM private.source_persona_identity i JOIN private.source_persona sp ON sp.id=i.source_persona_id
                 WHERE sp.source_id=-6620)
     OR (SELECT status FROM private.reimport_batch WHERE id=v_batch)<>'open'
     OR NOT private.persona_awaiting_control(pg_temp.pi_persona(w,1)) THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: inputdrift efterlod skrivning'; END IF;
  RAISE NOTICE 'OK: inputdrift ved finalize ruller hele C tilbage';
END $drift$;

-- 6) Writerens stikprøvetabel: en tabel med samme navn, som klienten selv har oprettet, godtages ikke.
DO $sampletable$
DECLARE
  w jsonb:=pg_temp.pi_world(-6630,'11000000-0000-0000-0000-00000006b630',1);
  v_run uuid; v_p jsonb; v_res text;
BEGIN
  v_run:=pg_temp.pi_run(w,'{"topK":10,"autoCutoff":0.9,"controlMargin":0.05}',
    jsonb_build_array(pg_temp.pi_cand(pg_temp.pi_persona(w,1),-6630001,1,jsonb_build_array(pg_temp.pi_ms(-6630001,0.95,ARRAY['name','birth'])))));
  v_p:=pg_temp.pi_payload(w,1,v_run,'enig','S');
  -- tabellen findes allerede fra blok 2-4 (writerens egen); den slettes som ejer og genskabes af klienten
  DROP TABLE IF EXISTS pg_temp.daa_publication_identity_sample;
  SET LOCAL ROLE authenticated;
  CREATE TEMP TABLE daa_publication_identity_sample(run_id uuid NOT NULL, source_persona_id uuid);
  RESET ROLE;
  PERFORM pg_temp.expect('klientens stikprøvetabel',pg_temp.pi_try(w,'smp',v_p),'PUBLICATION_IDENTITY_SAMPLE_MISMATCH');
  RAISE NOTICE 'OK: stikprøvetabellen skal være writerens';
END $sampletable$;

ROLLBACK;

-- 7) Codex 6B-02: writeren og finalize af C kræver READ COMMITTED; under REPEATABLE READ og SERIALIZABLE er snapshottet
--    taget før kandidatlåsen. SET TRANSACTION skal være transaktionens første sætning, så testen står i egne transaktioner
--    efter hovedtransaktionen (fixturefunktionerne i pg_temp overlever ROLLBACK). Kontrollen står først, så writeren
--    afviser, før batch eller payload læses; finalize afviser i verify_publication_identity_input, før kørslen læses.
BEGIN;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
DO $iso$
DECLARE v_src jsonb; w jsonb; v_batch uuid; v_res text;
BEGIN
  IF current_setting('transaction_isolation')<>'repeatable read' THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: isolationsniveau %',current_setting('transaction_isolation'); END IF;
  BEGIN PERFORM private.write_publication_identity(gen_random_uuid(),'publication-identity:x','{}'::jsonb); v_res:='OK';
  EXCEPTION WHEN OTHERS THEN v_res:=SQLERRM; END;
  IF v_res IS DISTINCT FROM 'PUBLICATION_IDENTITY_ISOLATION' THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: writer under repeatable read gav %',v_res; END IF;
  -- en åben C-batch med én publication_identity-hændelse (indsat som ejer; writeren afviser jo her), så finalize-tællingen
  -- stemmer og finalize når C's efterprøvning
  v_src:=pg_temp.pp_source(-6650,'11000000-0000-0000-0000-00000006b650'); w:=jsonb_build_object('src',v_src);
  v_batch:=pg_temp.pi_begin(w,'iso-rr',jsonb_build_object('publication-identity:x','{}'::jsonb));
  INSERT INTO private.reimport_event(batch_id,element_id,operation,source_record_key,payload,after_sha256)
    VALUES (v_batch,'publication-identity:x','publication_identity','x',
            jsonb_build_object('candidate_run_id',gen_random_uuid(),'persona_batch_id',gen_random_uuid()),repeat('e',64));
  BEGIN PERFORM pg_temp.pi_finalize(w,v_batch); v_res:='OK'; EXCEPTION WHEN OTHERS THEN v_res:=SQLERRM; END;
  IF v_res IS DISTINCT FROM 'PUBLICATION_IDENTITY_ISOLATION' THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: finalize under repeatable read gav %',v_res; END IF;
  IF (SELECT status FROM private.reimport_batch WHERE id=v_batch)<>'open' THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: batchen blev finaliseret under repeatable read'; END IF;
  RAISE NOTICE 'OK: REPEATABLE READ afvises af writer og finalize';
END $iso$;
ROLLBACK;

BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
DO $iso$
DECLARE v_res text;
BEGIN
  BEGIN PERFORM private.write_publication_identity(gen_random_uuid(),'publication-identity:x','{}'::jsonb); v_res:='OK';
  EXCEPTION WHEN OTHERS THEN v_res:=SQLERRM; END;
  IF v_res IS DISTINCT FROM 'PUBLICATION_IDENTITY_ISOLATION' THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: writer under serializable gav %',v_res; END IF;
  BEGIN PERFORM private.verify_publication_identity_input(gen_random_uuid()); v_res:='OK';
  EXCEPTION WHEN OTHERS THEN v_res:=SQLERRM; END;
  IF v_res IS DISTINCT FROM 'PUBLICATION_IDENTITY_ISOLATION' THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: efterprøvning under serializable gav %',v_res; END IF;
  RAISE NOTICE 'OK: SERIALIZABLE afvises af writer og finalize-efterprøvningen';
END $iso$;
ROLLBACK;

-- 8) Controller efter Codex 6B-01: en C-hændelse kan ikke committes uden finalize i samme transaktion. Ægte COMMIT: verden,
--    kørsel og én apply i én transaktion; COMMIT fejler med PUBLICATION_IDENTITY_UNFINALIZED, og intet er tilbage. En
--    tilsvarende transaktion, der rulles tilbage, er uberørt af vagten.
BEGIN;
DO $unfin$
DECLARE w jsonb:=pg_temp.pi_world(-6660,'11000000-0000-0000-0000-00000006b660',1); v_run uuid; v_p jsonb; v_batch uuid;
BEGIN
  v_run:=pg_temp.pi_run(w,'{"topK":10,"autoCutoff":0.9,"controlMargin":0.05}',
    jsonb_build_array(pg_temp.pi_cand(pg_temp.pi_persona(w,1),-6660001,1,jsonb_build_array(pg_temp.pi_ms(-6660001,0.95,ARRAY['name'])))));
  v_p:=pg_temp.pi_payload(w,1,v_run,'svag','S');
  v_batch:=pg_temp.pi_begin(w,'unfin',jsonb_build_object(pg_temp.pi_el(v_p),v_p));
  PERFORM pg_temp.pi_apply(w,v_batch,pg_temp.pi_el(v_p),v_p);
END $unfin$;
\echo 'Forventet: COMMIT nedenfor afvises med PUBLICATION_IDENTITY_UNFINALIZED'
\set ON_ERROR_STOP off
COMMIT;
\set ON_ERROR_STOP on
SELECT (:'LAST_ERROR_MESSAGE'='PUBLICATION_IDENTITY_UNFINALIZED'
        AND NOT EXISTS (SELECT 1 FROM public.source WHERE id=-6660)
        AND NOT EXISTS (SELECT 1 FROM public.person WHERE id=-6660001)) AS unfin_ok \gset
\if :unfin_ok
\echo 'OK: commit uden finalize afvises (PUBLICATION_IDENTITY_UNFINALIZED), intet tilbage'
\else
DO $f$ BEGIN RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: commit uden finalize blev ikke afvist rent'; END $f$;
\endif

BEGIN;
DO $rb$
DECLARE w jsonb:=pg_temp.pi_world(-6661,'11000000-0000-0000-0000-00000006b661',1); v_run uuid; v_p jsonb; v_batch uuid;
BEGIN
  v_run:=pg_temp.pi_run(w,'{"topK":10,"autoCutoff":0.9,"controlMargin":0.05}',
    jsonb_build_array(pg_temp.pi_cand(pg_temp.pi_persona(w,1),-6661001,1,jsonb_build_array(pg_temp.pi_ms(-6661001,0.95,ARRAY['name'])))));
  v_p:=pg_temp.pi_payload(w,1,v_run,'svag','S');
  v_batch:=pg_temp.pi_begin(w,'rb',jsonb_build_object(pg_temp.pi_el(v_p),v_p));
  PERFORM pg_temp.pi_apply(w,v_batch,pg_temp.pi_el(v_p),v_p);
END $rb$;
ROLLBACK;
DO $rbchk$
BEGIN
  IF EXISTS (SELECT 1 FROM public.source WHERE id=-6661) THEN
    RAISE EXCEPTION 'PUBLICATION_IDENTITY_TEST_FAILED: tilbagerullet transaktion efterlod data'; END IF;
  RAISE NOTICE 'OK: tilbagerullet transaktion med åben C er uberørt af commit-vagten';
END $rbchk$;
