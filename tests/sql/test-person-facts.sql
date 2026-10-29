-- 5c-2/B11 (spec 2026-10-29 §4.1, §7): public_person_facts og assertion_binding_current. Kører i writer-1939-jobbet.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/person-facts.sql

DO $person_facts$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000005c2b11'; m jsonb; m2 jsonb; r record; t record; v_ref uuid;
  v_sha text; v_v2 uuid; v_fp text; v_src2 jsonb; v_rec2 uuid; v_int2 uuid; pv jsonb; items jsonb; n int;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);

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

  -- (b) en ekstra supporting-observation på den bundne version
  m:=pg_temp.fpf_bound(-2721,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES ((m->>'interpretation')::uuid,(m->'post'->>'helpost')::uuid,'supporting',2);
  SELECT * INTO t FROM pg_temp.fpf_rows(-2721);
  IF t.n<>1 OR t.n_bundet<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (b) to observationer %',to_jsonb(t); END IF;

  -- (b2) anchoren gjort ikke-accepteret
  m:=pg_temp.fpf_bound(-2731,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
    VALUES ((m->'post'->>'occ')::uuid,(m->'post'->>'record')::uuid,'rejected','{"fixture":"fpf"}',2,v_actor,'fixture');
  SELECT * INTO t FROM pg_temp.fpf_rows(-2731);
  IF t.n<>1 OR t.n_bundet<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (b2) anchor afvist %',to_jsonb(t); END IF;

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

  -- (c2) narrativets publiceringsgate falsk (privat narrativ)
  m:=pg_temp.fpf_bound(-2761,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  UPDATE public.narrative SET privat=true
   WHERE id=(SELECT narrative_id FROM private.narrative_record_publication
              WHERE source_record_id=(m->'post'->>'record')::uuid AND status='published');
  IF NOT FOUND THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (c2) intet narrativ'; END IF;
  SELECT * INTO t FROM pg_temp.fpf_rows(-2761);
  IF t.n<>1 OR t.n_bundet<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (c2) privat narrativ %',to_jsonb(t); END IF;

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
  IF private.assertion_binding_current((m->>'promotion')::uuid)
     OR pg_temp.fpf_reason(m)<>'EVIDENCE_PROMOTION_VALUE_MISMATCH' THEN
    RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (d) enighed (%)',pg_temp.fpf_reason(m);
  END IF;

  -- (e) faktatype ændret som ejer
  m:=pg_temp.fpf_bound(-2781,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  UPDATE fact SET faktatype='fødsel' WHERE id=(m->>'fact')::bigint;
  SELECT * INTO t FROM pg_temp.fpf_rows(-2781);
  IF t.n<>1 OR t.n_bundet<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: (e) faktatype %',to_jsonb(t); END IF;
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

  -- konklusionsstatus: forældet ⇒ 0; omstridt uden valgt påstand ⇒ chosen IS FALSE
  m:=pg_temp.fpf_bound(-2841,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  UPDATE conclusion SET status='forældet' WHERE target_type='fact' AND target_id=(m->>'fact')::bigint;
  IF (pg_temp.fpf_rows(-2841)).n<>0 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: forældet'; END IF;
  UPDATE conclusion SET status='omstridt',valgt_assertion_id=NULL WHERE target_type='fact' AND target_id=(m->>'fact')::bigint;
  SELECT * INTO t FROM pg_temp.fpf_rows(-2841);
  IF t.n<>1 OR t.n_ikke_valgt<>1 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: omstridt %',to_jsonb(t); END IF;

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
  INSERT INTO citation(assertion_id,source_id,side) VALUES ((m->>'assertion')::bigint,-2851,'7'),((m->>'assertion')::bigint,-2851,'8');
  SET LOCAL ROLE anon;
  SELECT array_agg(side) INTO r FROM public.public_person_facts(ARRAY[-2851]);
  RESET ROLE;
  IF r.array_agg IS DISTINCT FROM ARRAY['7','8'] THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: to citationer %',r.array_agg; END IF;

  -- gemt regel, ikke aktiv (sidst: regeltabellen er append-only, og v99 ville ramme senere fixturer): en nyere aktiv version med anden forventet type ændrer ikke bindingen
  m:=pg_temp.fpf_bound(-2811,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  INSERT INTO private.interpretation_promotion_rule(rule_key,rule_version,predicate,interpretation_kind,target_type,
    expected_fact_type,value_kind,requires_persona_identity,requires_principal_placement,bulk_eligible,status)
    VALUES ('person-death-v1',99,'person.death','property','assertion','fødsel','date_raw',true,false,false,'active');
  SELECT * INTO t FROM pg_temp.fpf_rows(-2811);
  IF t.n<>1 OR t.n_bundet<>1 THEN RAISE EXCEPTION 'PERSON_FACTS_TEST_FAILED: gemt regel %',to_jsonb(t); END IF;

  RAISE NOTICE 'OK: public_person_facts og assertion_binding_current';
END $person_facts$;
ROLLBACK;
