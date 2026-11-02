-- 5c-2/B11 (spec 2026-10-29 §4.1, §7): public_person_facts og assertion_binding_current. Kører i writer-1939-jobbet.
-- Trin 6c-2a (vej B, spec 2026-11-02 §4.1): rækkelighed med den frosne reference og ingen kald af enkeltopslaget pr. række.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/person-facts.sql
\ir fixtures/public_person_facts_reference.sql

-- Trin 6c-2a (vej B): public_person_facts skal give præcis samme rækker som den frosne reference (main), med
-- dubletter talt med (EXCEPT ALL begge veje). Kaldes som ejer; begge er SECURITY DEFINER.
CREATE OR REPLACE FUNCTION pg_temp.fpf_equal(p_ids bigint[]) RETURNS void LANGUAGE plpgsql AS $$
DECLARE n_new int; n_ref int; n_a int; n_b int;
BEGIN
  SELECT count(*) INTO n_new FROM public.public_person_facts(p_ids);
  SELECT count(*) INTO n_ref FROM pg_temp.public_person_facts_ref(p_ids);
  SELECT count(*) INTO n_a FROM (SELECT * FROM public.public_person_facts(p_ids)
                                 EXCEPT ALL SELECT * FROM pg_temp.public_person_facts_ref(p_ids)) x;
  SELECT count(*) INTO n_b FROM (SELECT * FROM pg_temp.public_person_facts_ref(p_ids)
                                 EXCEPT ALL SELECT * FROM public.public_person_facts(p_ids)) x;
  IF n_new<>n_ref OR n_a<>0 OR n_b<>0 THEN
    RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: vej B ulig referencen for % (ny %, ref %, kun ny %, kun ref %)',
      p_ids,n_new,n_ref,n_a,n_b;
  END IF;
END $$;

-- Antal kald af assertion_binding_current i denne transaktion (track_functions='all' sættes af testen).
CREATE OR REPLACE FUNCTION pg_temp.fpf_abc_calls() RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT s.calls FROM pg_stat_xact_user_functions s
                    WHERE s.funcid='private.assertion_binding_current(uuid)'::regprocedure),0)
$$;

-- En ekstra binding på en eksisterende person fra en anden kilde (fx 1939 ved siden af 2018-20): kilde, post med
-- publiceret narrativ for personen, et faktum med påstand og citation, og en accepteret og promoveret fortolkning.
-- p_value er fortolkningens værdi; p_kind er 'text' (vaerdi_tekst) eller 'date_raw'. Flere faktum kan dele kilden:
-- første kald (p_post NULL) opretter kilde og post. Kald som ejer.
CREATE OR REPLACE FUNCTION pg_temp.fpf_extra(p_person bigint,p_source bigint,p_actor uuid,p_post jsonb,p_clause int,
  p_faktatype text,p_predicate text,p_kind text,p_assert_value text,p_value text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE s jsonb; post jsonb:=p_post; v_text text:='Anna Alfa. Født 1801.'; v_fact bigint; v_assert bigint;
  v_int uuid:=gen_random_uuid(); v_key uuid:=gen_random_uuid(); pv jsonb; items jsonb; v_prom uuid;
BEGIN
  IF post IS NULL THEN
    s:=pg_temp.f5b_source(p_source);
    UPDATE public.source SET udgave='DAA fpf '||abs(p_source) WHERE id=p_source;
    post:=pg_temp.f5b_post(p_source,s,'P'||abs(p_source),v_text,ARRAY['Anna Alfa.','Født 1801.'],p_person,p_actor)
          ||jsonb_build_object('src',s);
    PERFORM pg_temp.f2a_event_for_state((post->>'principal')::uuid);
    PERFORM pg_temp.f2a_publish(p_source,s,post,p_person,p_actor,v_text);
  END IF;
  s:=post->'src';
  INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',p_person,p_faktatype) RETURNING id INTO v_fact;
  IF p_kind='text' THEN
    INSERT INTO assertion(target_type,target_id,vaerdi_tekst,uforanderlig)
      VALUES ('fact',v_fact,p_assert_value,true) RETURNING id INTO v_assert;
  ELSE
    INSERT INTO assertion(target_type,target_id,date_raw,calendar,uforanderlig)
      VALUES ('fact',v_fact,p_assert_value,'gregoriansk',true) RETURNING id INTO v_assert;
  END IF;
  INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_fact,v_assert,'afklaret');
  INSERT INTO citation(assertion_id,source_id,citat_tekst,side) VALUES (v_assert,p_source,'fpf','3');
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
    predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES (v_int,v_key,1,p_source,(post->>'principal')::uuid,'property',p_predicate,to_jsonb(p_value),'1.0',
      'source_statement',1,'proposed','fixture',(s->>'run')::uuid);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_int,(post->'clauses'->>p_clause)::uuid,'supporting',1);
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_decide_interpretation(v_int,1,'accepted','{"basis":"fpf extra"}');
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  SELECT ic.id INTO v_int FROM private.interpretation_current ic WHERE ic.interpretation_key=v_key;
  SET LOCAL ROLE authenticated;
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_int::text,'target_type','assertion','target_id',v_assert));
  pv:=public.red_preview_interpretation_promotions(items);
  PERFORM public.red_promote_interpretations_batch(items,pv->>'preview_hash');
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  SELECT id INTO v_prom FROM private.interpretation_promotion
   WHERE interpretation_id=v_int AND target_type='assertion' AND target_id=v_assert;
  IF v_prom IS NULL THEN RAISE EXCEPTION 'FPF_EXTRA: ingen promotion (%)',p_predicate; END IF;
  RETURN jsonb_build_object('post',post,'fact',v_fact,'assertion',v_assert,'interpretation',v_int,
    'interpretation_key',v_key,'promotion',v_prom);
END $$;

DO $person_facts$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000005c2b11'; m jsonb; m2 jsonb; r record; t record; v_ref uuid;
  v_sha text; v_v2 uuid; v_fp text; v_src2 jsonb; v_rec2 uuid; v_int2 uuid; pv jsonb; items jsonb; n int;
  x1 jsonb; x2 jsonb; c0 bigint; c1 bigint; c2 bigint;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  PERFORM set_config('track_functions','all',true);

  -- (1) lykkelig sti: én bundet række, som anon og authenticated
  m:=pg_temp.fpf_bound(-2701,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  SELECT public_ref INTO v_ref FROM private.source_record WHERE id=(m->'post'->>'record')::uuid;
  SET LOCAL ROLE anon;
  SELECT * INTO r FROM public.public_person_facts(ARRAY[-2701]);
  RESET ROLE;
  IF r.fact_id IS DISTINCT FROM (m->>'fact')::bigint OR r.faktatype<>'død' OR r.conclusion_status<>'afklaret'
     OR r.chosen IS NOT TRUE OR r.date_raw<>'1850' OR r.source_id<>-2701 OR r.source_label<>'DAA fpf'
     OR r.record_ref IS DISTINCT FROM v_ref OR v_ref IS NULL
     OR nullif(r.record_label,'') IS NULL OR nullif(r.citation_label,'') IS NULL THEN
    RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: lykkelig sti %',to_jsonb(r);
  END IF;
  SELECT * INTO t FROM pg_temp.fpf_rows(-2701,'authenticated');
  IF t.n<>1 OR t.n_bundet<>1 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: authenticated %',to_jsonb(t); END IF;
  PERFORM pg_temp.fpf_equal(ARRAY[-2701]);
  IF NOT private.assertion_binding_current((m->>'promotion')::uuid)
     OR pg_temp.fpf_reason(m)<>'EVIDENCE_PROMOTION_ALREADY_PROMOTED' THEN
    RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: enighed ubrudt (%)',pg_temp.fpf_reason(m);
  END IF;

  -- (2) kontrakt 1 og NULL-input ⇒ 0
  CREATE OR REPLACE FUNCTION public.narrative_record_contract_version() RETURNS integer
    LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $c$ SELECT 1 $c$;
  IF (pg_temp.fpf_rows(-2701)).n<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: kontrakt 1'; END IF;
  CREATE OR REPLACE FUNCTION public.narrative_record_contract_version() RETURNS integer
    LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $c$ SELECT 2 $c$;
  SET LOCAL ROLE anon;
  SELECT count(*) INTO n FROM public.public_person_facts(NULL);
  RESET ROLE;
  IF n<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: NULL-input'; END IF;

  -- (a) fortolkningen superseded af en ny version ⇒ faktum uden binding
  m:=pg_temp.fpf_bound(-2711,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v_v2:=gen_random_uuid();
  INSERT INTO private.interpretation(id,interpretation_key,version,supersedes_id,source_id,source_persona_id,
    interpretation_kind,predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
  SELECT v_v2,ic.interpretation_key,ic.version+1,ic.id,ic.source_id,ic.source_persona_id,ic.interpretation_kind,
         ic.predicate,ic.value,ic.schema_version,ic.derivation_kind,ic.confidence,'proposed',ic.method,ic.extraction_run_id
    FROM private.interpretation_current ic WHERE ic.interpretation_key=(m->>'interpretation_key')::uuid;
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_v2,(m->'post'->'clauses'->>0)::uuid,'supporting',1);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  SELECT * INTO t FROM pg_temp.fpf_rows(-2711);
  IF t.n<>1 OR t.n_bundet<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (a) superseded %',to_jsonb(t); END IF;
  PERFORM pg_temp.fpf_equal(ARRAY[-2711]);

  -- (b) en ekstra supporting-observation på den bundne version
  m:=pg_temp.fpf_bound(-2721,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES ((m->>'interpretation')::uuid,(m->'post'->>'helpost')::uuid,'supporting',2);
  SELECT * INTO t FROM pg_temp.fpf_rows(-2721);
  IF t.n<>1 OR t.n_bundet<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (b) to observationer %',to_jsonb(t); END IF;
  PERFORM pg_temp.fpf_equal(ARRAY[-2721]);

  -- (b2) anchoren gjort ikke-accepteret
  m:=pg_temp.fpf_bound(-2731,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
    VALUES ((m->'post'->>'occ')::uuid,(m->'post'->>'record')::uuid,'rejected','{"fixture":"fpf"}',2,v_actor,'fixture');
  SELECT * INTO t FROM pg_temp.fpf_rows(-2731);
  IF t.n<>1 OR t.n_bundet<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (b2) anchor afvist %',to_jsonb(t); END IF;
  PERFORM pg_temp.fpf_equal(ARRAY[-2731]);

  -- (b3) en anchor til en record i en anden kilde kan ikke skrives (trigger EVIDENCE_SOURCE_MISMATCH); betingelse 2's
  -- kildekrav er derfor forsvar i dybden. Testen låser, at skemaet afviser tilstanden.
  m:=pg_temp.fpf_bound(-2741,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v_src2:=pg_temp.f5b_source(-2745);
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id)
    VALUES (-2745,'X2745','person_post',(v_src2->>'run')::uuid) RETURNING id INTO v_rec2;
  BEGIN
    INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
      VALUES ((m->'post'->>'occ')::uuid,v_rec2,'accepted','{"fixture":"fpf"}',1,v_actor,'fixture');
    RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (b3) anchor på tværs af kilder blev skrevet';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'EVIDENCE_SOURCE_MISMATCH%' THEN RAISE; END IF;
  END;

  -- (c) publiceringen trukket tilbage gennem redaktions-RPC'en
  m:=pg_temp.fpf_bound(-2751,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v_sha:=private.narrative_record_state(-2751,-2751,m->'post'->>'key',true)->>'state_sha256';
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_tilbagetraek_person_narrative_record(-2751,-2751,m->'post'->>'key',v_sha);
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  SELECT * INTO t FROM pg_temp.fpf_rows(-2751);
  IF t.n<>1 OR t.n_bundet<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (c) tilbagetrukket %',to_jsonb(t); END IF;
  PERFORM pg_temp.fpf_equal(ARRAY[-2751]);

  -- (c2) narrativets publiceringsgate falsk (privat narrativ)
  m:=pg_temp.fpf_bound(-2761,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  UPDATE public.narrative SET privat=true
   WHERE id=(SELECT narrative_id FROM private.narrative_record_publication
              WHERE source_record_id=(m->'post'->>'record')::uuid AND status='published');
  IF NOT FOUND THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (c2) intet narrativ'; END IF;
  SELECT * INTO t FROM pg_temp.fpf_rows(-2761);
  IF t.n<>1 OR t.n_bundet<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (c2) privat narrativ %',to_jsonb(t); END IF;
  PERFORM pg_temp.fpf_equal(ARRAY[-2761]);

  -- (d) OCR-rettelse af den bundne assertions dødsdato på samme assertion-id (B12)
  m:=pg_temp.fpf_bound(-2771,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  SELECT private.ocr_fingerprint(m->>'import_key',m->>'record_key','doed',
           private.ocr_importeret('doed',a.vaerdi_tekst,a.date_raw,a.date_min,a.date_max,a.date_qualifier,a.calendar,a.date_certainty),
           c.citat_tekst)
    INTO v_fp FROM assertion a JOIN citation c ON c.assertion_id=a.id WHERE a.id=(m->>'assertion')::bigint;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_ret_ocr_felt(-2771,m->>'import_key',m->>'record_key','doed',v_fp,'{"raw":"1851"}'::jsonb);
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  IF (SELECT date_raw FROM assertion WHERE id=(m->>'assertion')::bigint)<>'1851' THEN
    RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (d) OCR-rettelsen blev ikke skrevet';
  END IF;
  SELECT * INTO t FROM pg_temp.fpf_rows(-2771);
  IF t.n<>1 OR t.n_bundet<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (d) OCR %',to_jsonb(t); END IF;
  PERFORM pg_temp.fpf_equal(ARRAY[-2771]);
  IF private.assertion_binding_current((m->>'promotion')::uuid)
     OR pg_temp.fpf_reason(m)<>'EVIDENCE_PROMOTION_VALUE_MISMATCH' THEN
    RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (d) enighed (%)',pg_temp.fpf_reason(m);
  END IF;

  -- (e) faktatype ændret som ejer
  m:=pg_temp.fpf_bound(-2781,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  UPDATE fact SET faktatype='fødsel' WHERE id=(m->>'fact')::bigint;
  SELECT * INTO t FROM pg_temp.fpf_rows(-2781);
  IF t.n<>1 OR t.n_bundet<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (e) faktatype %',to_jsonb(t); END IF;
  PERFORM pg_temp.fpf_equal(ARRAY[-2781]);
  IF private.assertion_binding_current((m->>'promotion')::uuid)
     OR pg_temp.fpf_reason(m)<>'EVIDENCE_PROMOTION_FACT_TYPE_MISMATCH' THEN
    RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (e) enighed (%)',pg_temp.fpf_reason(m);
  END IF;

  -- (e2) faktummet flyttet til en anden offentlig person (identitetsbrud)
  m:=pg_temp.fpf_bound(-2791,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  UPDATE fact SET subjekt_id=-2792 WHERE id=(m->>'fact')::bigint;
  IF (pg_temp.fpf_rows(-2791)).n<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (e2) faktum blev hos personen'; END IF;
  SELECT * INTO t FROM pg_temp.fpf_rows(-2792);
  IF t.n<>1 OR t.n_bundet<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (e2) identitet %',to_jsonb(t); END IF;
  PERFORM pg_temp.fpf_equal(ARRAY[-2791,-2792]);
  IF private.assertion_binding_current((m->>'promotion')::uuid)
     OR pg_temp.fpf_reason(m)<>'EVIDENCE_PROMOTION_IDENTITY_MISMATCH' THEN
    RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (e2) enighed (%)',pg_temp.fpf_reason(m);
  END IF;

  -- (f) narrativets subjekt sat til en anden person (betingelse 3 alene; syntetisk)
  m:=pg_temp.fpf_bound(-2801,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  UPDATE public.narrative SET subjekt_id=-2802
   WHERE id=(SELECT narrative_id FROM private.narrative_record_publication
              WHERE source_record_id=(m->'post'->>'record')::uuid AND status='published');
  SELECT * INTO t FROM pg_temp.fpf_rows(-2801);
  IF t.n<>1 OR t.n_bundet<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (f) andet subjekt %',to_jsonb(t); END IF;
  PERFORM pg_temp.fpf_equal(ARRAY[-2801]);
  IF NOT private.assertion_binding_current((m->>'promotion')::uuid) THEN
    RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (f) hjælperen skal ikke se betingelse 3';
  END IF;

  -- entydighed: to gyldige promotions på samme assertion ⇒ ingen binding og ingen dubletrækker
  m:=pg_temp.fpf_bound(-2821,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v_int2:=gen_random_uuid();
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
    predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES (v_int2,gen_random_uuid(),1,-2821,(m->'post'->>'principal')::uuid,'property','person.death',
      to_jsonb('1850'::text),'1.0','source_statement',1,'proposed','fixture',(m->'src'->>'run')::uuid);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_int2,(m->'post'->'clauses'->>0)::uuid,'supporting',1);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_decide_interpretation(v_int2,1,'accepted','{"basis":"fpf 2"}');
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  SELECT ic.id INTO v_int2 FROM private.interpretation_current ic
   WHERE ic.interpretation_key=(SELECT interpretation_key FROM private.interpretation WHERE id=v_int2);
  SET LOCAL ROLE authenticated;
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_int2::text,'target_type','assertion',
    'target_id',(m->>'assertion')::bigint));
  pv:=public.red_preview_interpretation_promotions(items);
  PERFORM public.red_promote_interpretations_batch(items,pv->>'preview_hash');
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  SELECT * INTO t FROM pg_temp.fpf_rows(-2821);
  IF t.n<>1 OR t.n_bundet<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: to promotions %',to_jsonb(t); END IF;
  PERFORM pg_temp.fpf_equal(ARRAY[-2821]);

  -- gate: levende og privat ⇒ 0, som anon og authenticated
  m:=pg_temp.fpf_bound(-2831,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  UPDATE person SET levende=true WHERE id=-2831;
  IF (pg_temp.fpf_rows(-2831)).n<>0 OR (pg_temp.fpf_rows(-2831,'authenticated')).n<>0 THEN
    RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: levende';
  END IF;
  UPDATE person SET levende=false,privat=true WHERE id=-2831;
  IF (pg_temp.fpf_rows(-2831)).n<>0 OR (pg_temp.fpf_rows(-2831,'authenticated')).n<>0 THEN
    RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: privat';
  END IF;
  PERFORM pg_temp.fpf_equal(ARRAY[-2831]);

  -- konklusionsstatus: forældet ⇒ 0; omstridt uden valgt påstand ⇒ chosen IS FALSE
  m:=pg_temp.fpf_bound(-2841,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  UPDATE conclusion SET status='forældet' WHERE target_type='fact' AND target_id=(m->>'fact')::bigint;
  IF (pg_temp.fpf_rows(-2841)).n<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: forældet'; END IF;
  UPDATE conclusion SET status='omstridt',valgt_assertion_id=NULL WHERE target_type='fact' AND target_id=(m->>'fact')::bigint;
  SELECT * INTO t FROM pg_temp.fpf_rows(-2841);
  IF t.n<>1 OR t.n_ikke_valgt<>1 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: omstridt %',to_jsonb(t); END IF;
  PERFORM pg_temp.fpf_equal(ARRAY[-2841]);

  -- kilde: uden udgave ⇒ titel; citation uden kilde; assertion uden citation; to citationer i id-orden
  m:=pg_temp.fpf_bound(-2851,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  UPDATE public.source SET udgave=NULL WHERE id=-2851;
  SET LOCAL ROLE anon;
  SELECT * INTO r FROM public.public_person_facts(ARRAY[-2851]);
  RESET ROLE;
  IF r.source_label IS DISTINCT FROM '5b fixture' THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: titel som label %',r.source_label; END IF;
  UPDATE citation SET source_id=NULL WHERE assertion_id=(m->>'assertion')::bigint;
  SET LOCAL ROLE anon;
  SELECT * INTO r FROM public.public_person_facts(ARRAY[-2851]);
  RESET ROLE;
  IF r.source_id IS NOT NULL OR r.source_label IS NOT NULL THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: citation uden kilde'; END IF;
  DELETE FROM citation WHERE assertion_id=(m->>'assertion')::bigint;
  SELECT * INTO t FROM pg_temp.fpf_rows(-2851);
  IF t.n<>1 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: uden citation %',to_jsonb(t); END IF;
  PERFORM pg_temp.fpf_equal(ARRAY[-2851]);
  INSERT INTO citation(assertion_id,source_id,side) VALUES ((m->>'assertion')::bigint,-2851,'7'),((m->>'assertion')::bigint,-2851,'8');
  SET LOCAL ROLE anon;
  SELECT array_agg(side) INTO r FROM public.public_person_facts(ARRAY[-2851]);
  RESET ROLE;
  IF r.array_agg IS DISTINCT FROM ARRAY['7','8'] THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: to citationer %',r.array_agg; END IF;

  -- Trin 6c-2a (vej B, Review Focus 1): én person med en gyldig binding fra sin egen kilde, en gyldig tekstbinding
  -- fra en anden kilde (som 1939 ved siden af 2018-20) og en ugyldig binding imellem (fortolkningen fået en ny
  -- version, som (a)). Vej B skal give præcis referencens rækker og kildelinjer.
  m:=pg_temp.fpf_bound(-2861,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  x1:=pg_temp.fpf_extra(-2861,-2865,v_actor,NULL,0,'navn','person.name','text','Anna Alfa',' anna ALFA ');
  x2:=pg_temp.fpf_extra(-2861,-2865,v_actor,x1->'post',1,'fødsel','person.birth','date_raw','1801','1801');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF NOT private.assertion_binding_current((x1->>'promotion')::uuid)
     OR NOT private.assertion_binding_current((x2->>'promotion')::uuid) THEN
    RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: blandet person, bindinger ikke gyldige før ugyldiggørelsen';
  END IF;
  v_v2:=gen_random_uuid();
  INSERT INTO private.interpretation(id,interpretation_key,version,supersedes_id,source_id,source_persona_id,
    interpretation_kind,predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
  SELECT v_v2,ic.interpretation_key,ic.version+1,ic.id,ic.source_id,ic.source_persona_id,ic.interpretation_kind,
         ic.predicate,ic.value,ic.schema_version,ic.derivation_kind,ic.confidence,'proposed',ic.method,ic.extraction_run_id
    FROM private.interpretation_current ic WHERE ic.interpretation_key=(x2->>'interpretation_key')::uuid;
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_v2,(x2->'post'->'clauses'->>1)::uuid,'supporting',1);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF NOT private.assertion_binding_current((m->>'promotion')::uuid)
     OR NOT private.assertion_binding_current((x1->>'promotion')::uuid)
     OR private.assertion_binding_current((x2->>'promotion')::uuid) THEN
    RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: blandet person, enkeltopslaget';
  END IF;
  SELECT * INTO t FROM pg_temp.fpf_rows(-2861);
  IF t.n<>3 OR t.n_bundet<>2 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: blandet person %',to_jsonb(t); END IF;
  SET LOCAL ROLE anon;
  SELECT count(DISTINCT source_id) INTO n FROM public.public_person_facts(ARRAY[-2861]) WHERE record_ref IS NOT NULL;
  RESET ROLE;
  IF n<>2 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: blandet person, bundne kilder %',n; END IF;
  PERFORM pg_temp.fpf_equal(ARRAY[-2861]);

  -- gemt regel, ikke aktiv (sidst: regeltabellen er append-only, og v99 ville ramme senere fixturer): en nyere aktiv version med anden forventet type ændrer ikke bindingen
  m:=pg_temp.fpf_bound(-2811,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  INSERT INTO private.interpretation_promotion_rule(rule_key,rule_version,predicate,interpretation_kind,target_type,
    expected_fact_type,value_kind,requires_persona_identity,requires_principal_placement,bulk_eligible,status)
    VALUES ('person-death-v1',99,'person.death','property','assertion','fødsel','date_raw',true,false,false,'active');
  SELECT * INTO t FROM pg_temp.fpf_rows(-2811);
  IF t.n<>1 OR t.n_bundet<>1 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: gemt regel %',to_jsonb(t); END IF;
  PERFORM pg_temp.fpf_equal(ARRAY[-2811]);

  -- Trin 6c-2a (vej B): alle fixturpersoner samlet, og ingen kald af enkeltopslaget pr. promotion-række. Referencen
  -- skal kalde det (ellers måler instrumentet intet); den nye funktion må ikke.
  PERFORM pg_temp.fpf_equal(ARRAY(SELECT id FROM person WHERE id BETWEEN -2900 AND -2700 ORDER BY id));
  c0:=pg_temp.fpf_abc_calls();
  PERFORM count(*) FROM pg_temp.public_person_facts_ref(ARRAY[-2861]);
  c1:=pg_temp.fpf_abc_calls();
  PERFORM count(*) FROM public.public_person_facts(ARRAY[-2861]);
  c2:=pg_temp.fpf_abc_calls();
  IF c1-c0<2 THEN
    RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: instrumentet ser ikke referencens kald (% kald)',c1-c0;
  END IF;
  IF c2-c1<>0 THEN
    RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: VEJ_B_PER_ROW public_person_facts kalder assertion_binding_current pr. promotion-række (% kald)',c2-c1;
  END IF;

  RAISE NOTICE 'OK: public_person_facts og assertion_binding_current';
END $person_facts$;
ROLLBACK;
