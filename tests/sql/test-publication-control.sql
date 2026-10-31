-- Trin 6b Task 5: oprindelsen publication_binding i identitetskernen, klassifikatoren for publiceringskontrollen,
-- den blinde stikprøve og kontrolarkets to læse-RPC'er. Kræver kontrakt v2 (reimport-writer-v2-bootstrap.sql) som
-- test-publication-persona.sql, fordi B-personas skrives gennem den rigtige writer. Alt syntetisk; én transaktion,
-- rulles tilbage. Ingen navne eller posttekst i output.
\set ON_ERROR_STOP on
\i tests/sql/fixtures/publication-persona.sql
BEGIN;

CREATE FUNCTION pg_temp.el(p_key text) RETURNS text LANGUAGE sql AS $$ SELECT 'publication-persona:'||p_key $$;

-- Kernen direkte som ejer (= serverfunktionernes rettighed) med redaktørens jwt-sub; returnerer 'OK' eller fejlteksten.
CREATE FUNCTION pg_temp.kerne(p_actor text, p_persona uuid, p_person bigint, p_ver int, p_status text, p_ev jsonb, p_origin text)
RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_actor,true);
  PERFORM private.decide_source_persona_identity(p_persona,p_person,p_ver,p_status,p_ev,p_origin);
  RETURN 'OK';
EXCEPTION WHEN OTHERS THEN RETURN SQLERRM;
END $$;

CREATE FUNCTION pg_temp.persona(p_source bigint, p_run uuid, p_key text, p_mention uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES (p_source,p_key,p_run) RETURNING id INTO v;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v,p_mention,'primary',1);
  RETURN v;
END $$;

-- Syntetisk kandidatkørsel og -række (som ejer): basis bærer member_scores som generatoren (Task 9).
CREATE FUNCTION pg_temp.pc_run(p_source bigint, p_config jsonb, p_tag text, p_spec jsonb DEFAULT '{"mode":"undecided"}') RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO private.source_persona_identity_candidate_run(source_id,generator_version,config,config_sha256,input_spec,
    input_sha256,candidates_sha256,persona_count,candidate_count,created_by,created_by_name)
  VALUES (p_source,'t',p_config,private.reimport_canonical_json_sha256(p_config),p_spec,
          encode(extensions.digest('input:'||p_tag,'sha256'),'hex'),repeat('c',64),0,0,gen_random_uuid(),'t')
  RETURNING id INTO v;
  RETURN v;
END $$;

CREATE FUNCTION pg_temp.ms(p_person bigint, p_score numeric, p_signals text[]) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('person_id',p_person,'score_raw',p_score,'signals',to_jsonb(p_signals))
$$;

CREATE FUNCTION pg_temp.pc_cand(p_run uuid, p_persona uuid, p_rep bigint, p_rank int, p_members jsonb) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO private.source_persona_identity_candidate(run_id,source_persona_id,candidate_person_id,rank,score,tier,basis)
  VALUES (p_run,p_persona,p_rep,p_rank,
          round(least(1,(SELECT max((e->>'score_raw')::numeric) FROM jsonb_array_elements(p_members) e)),4),'review',
          jsonb_build_object('signals',jsonb_build_array('name'),'member_scores',p_members));
END $$;

CREATE FUNCTION pg_temp.outcome(p_persona uuid, p_run uuid, p_person bigint) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN RETURN private.publication_control_outcome(p_persona,p_run,p_person);
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error',SQLERRM);
END $$;

CREATE FUNCTION pg_temp.rpc(p_actor text, p_fn text, p_run uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',coalesce(p_actor,''),true);
  PERFORM set_config('role','authenticated',true);
  EXECUTE format('SELECT public.%I($1)',p_fn) INTO v USING p_run;
  RESET role; RETURN v;
EXCEPTION WHEN OTHERS THEN RESET role; RETURN jsonb_build_object('error',SQLERRM);
END $$;

-- 0) Fladen: funktionerne findes, hjælperne er private, RPC'erne kun for authenticated.
DO $surface$
BEGIN
  IF to_regprocedure('private.publication_control_outcome(uuid,uuid,bigint)') IS NULL
     OR to_regprocedure('private.publication_control_in_sample(uuid,uuid)') IS NULL
     OR to_regprocedure('public.red_publication_control(uuid)') IS NULL
     OR to_regprocedure('public.red_publication_control_details(uuid)') IS NULL THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: funktioner mangler'; END IF;
  IF has_function_privilege('authenticated','private.publication_control_outcome(uuid,uuid,bigint)','EXECUTE')
     OR has_function_privilege('authenticated','private.publication_control_in_sample(uuid,uuid)','EXECUTE')
     OR has_function_privilege('anon','public.red_publication_control(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.red_publication_control_details(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_publication_control(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_publication_control_details(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: rettigheder'; END IF;
  RAISE NOTICE 'OK: funktionsfladen';
END $surface$;

-- 1) Kernen: oprindelsen publication_binding og hver ugyldig variant.
DO $kerne$
DECLARE
  v_src jsonb:=pg_temp.pp_source(-6510,'11000000-0000-0000-0000-00000006b510');
  v_a text:='11000000-0000-0000-0000-00000006b510'; v_run uuid;
  v_k1 jsonb; v_kd jsonb; v_ke jsonb; v_ko jsonb; v_kx jsonb; v_km jsonb; v_ka jsonb;
  p_k1 uuid; p_kd uuid; p_ke uuid; p_ko uuid; p_km uuid; p_ka uuid; v_dummy uuid;
  v_ev jsonb; v_res text; v_case text; v_i int; v_row private.source_persona_identity%ROWTYPE;
BEGIN
  v_run:=(v_src->>'run')::uuid;
  v_k1:=pg_temp.pp_post(v_src,'k1',-651001);
  v_kd:=pg_temp.pp_post(v_src,'kd',-651002,'{"binding":"draft"}');
  v_ke:=pg_temp.pp_post(v_src,'ke',-651003,'{"ext_ids":0}');
  v_ko:=pg_temp.pp_post(v_src,'ko',-651004);
  v_kx:=pg_temp.pp_post(v_src,'kx',-651005);
  v_km:=pg_temp.pp_post(v_src,'km',-651006);
  v_ka:=pg_temp.pp_post(v_src,'ka',-651007);
  PERFORM pg_temp.pp_occ((v_ka->>'record')::uuid,v_src,'ka-h2',600,900,'person');   -- to helpost-kandidater: flertydig
  p_k1:=pg_temp.persona(-6510,v_run,'1939:k1',(v_k1->>'mention')::uuid);
  p_kd:=pg_temp.persona(-6510,v_run,'1939:kd',(v_kd->>'mention')::uuid);
  p_ke:=pg_temp.persona(-6510,v_run,'1939:ke',(v_ke->>'mention')::uuid);
  p_ko:=pg_temp.persona(-6510,v_run,'1939:ko',(v_ko->>'mention')::uuid);
  v_dummy:=pg_temp.persona(-6510,v_run,'anden-form:ko',(v_ko->>'mention')::uuid);   -- en anden persona i samme helpost
  p_km:=pg_temp.persona(-6510,v_run,'1939:km',(v_kx->>'mention')::uuid);              -- mention i kx's helpost, ikke km's
  p_ka:=pg_temp.persona(-6510,v_run,'1939:ka',(v_ka->>'mention')::uuid);

  v_ev:=jsonb_build_object('authority','narrative_record_publication','binding_id',v_k1->>'binding');
  FOR v_case IN SELECT unnest(ARRAY['status','basis','autoritet','uden_binding','skrald_binding','fremmed_binding','anden_person',
                                    'draft','ingen_pei','anden_persona','mention_udenfor','flertydig']) LOOP
    v_res:=CASE v_case
      WHEN 'status' THEN pg_temp.kerne(v_a,p_k1,NULL,0,'unresolved',v_ev,'publication_binding')
      WHEN 'basis' THEN pg_temp.kerne(v_a,p_k1,-651001,0,'accepted',v_ev||'{"basis":"human_sheet"}','publication_binding')
      WHEN 'autoritet' THEN pg_temp.kerne(v_a,p_k1,-651001,0,'accepted',v_ev||'{"authority":"person_external_id"}','publication_binding')
      WHEN 'uden_binding' THEN pg_temp.kerne(v_a,p_k1,-651001,0,'accepted',v_ev-'binding_id','publication_binding')
      WHEN 'skrald_binding' THEN pg_temp.kerne(v_a,p_k1,-651001,0,'accepted',v_ev||'{"binding_id":"ikke-en-uuid"}','publication_binding')
      WHEN 'fremmed_binding' THEN pg_temp.kerne(v_a,p_k1,-651001,0,'accepted',v_ev||jsonb_build_object('binding_id',v_ko->>'binding'),'publication_binding')
      WHEN 'anden_person' THEN pg_temp.kerne(v_a,p_k1,-651002,0,'accepted',v_ev,'publication_binding')
      WHEN 'draft' THEN pg_temp.kerne(v_a,p_kd,-651002,0,'accepted',v_ev||jsonb_build_object('binding_id',v_kd->>'binding'),'publication_binding')
      WHEN 'ingen_pei' THEN pg_temp.kerne(v_a,p_ke,-651003,0,'accepted',v_ev||jsonb_build_object('binding_id',v_ke->>'binding'),'publication_binding')
      WHEN 'anden_persona' THEN pg_temp.kerne(v_a,p_ko,-651004,0,'accepted',v_ev||jsonb_build_object('binding_id',v_ko->>'binding'),'publication_binding')
      WHEN 'mention_udenfor' THEN pg_temp.kerne(v_a,p_km,-651006,0,'accepted',v_ev||jsonb_build_object('binding_id',v_km->>'binding'),'publication_binding')
      WHEN 'flertydig' THEN pg_temp.kerne(v_a,p_ka,-651007,0,'accepted',v_ev||jsonb_build_object('binding_id',v_ka->>'binding'),'publication_binding')
    END;
    IF v_res IS DISTINCT FROM 'PUBLICATION_BINDING_ORIGIN_INVALID' THEN
      RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: kerne-% gav %',v_case,v_res; END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM private.source_persona_identity WHERE source_persona_id IN (p_k1,p_kd,p_ke,p_ko,p_km,p_ka)) THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: afvist kernekald skrev en identitet'; END IF;

  -- den gyldige lykkes; reversal til superseded virker bagefter; derefter afvises en ny publication_binding (version ≠ 0)
  v_res:=pg_temp.kerne(v_a,p_k1,-651001,0,'accepted',v_ev,'publication_binding');
  IF v_res<>'OK' THEN RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: gyldig publication_binding: %',v_res; END IF;
  SELECT * INTO v_row FROM private.source_persona_identity WHERE source_persona_id=p_k1;
  IF v_row.decision_status<>'accepted' OR v_row.canonical_person_id<>-651001 OR v_row.version<>1 OR v_row.evidence<>v_ev THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: identitetsrækken'; END IF;
  v_res:=pg_temp.kerne(v_a,p_k1,NULL,1,'superseded','{"reversed_batch_id":"00000000-0000-0000-0000-000000000001"}','reversal');
  IF v_res<>'OK' THEN RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: reversal: %',v_res; END IF;
  v_res:=pg_temp.kerne(v_a,p_k1,-651001,2,'accepted',v_ev,'publication_binding');
  IF v_res IS DISTINCT FROM 'PUBLICATION_BINDING_ORIGIN_INVALID' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: version 2 gav %',v_res; END IF;
  RAISE NOTICE 'OK: kernen (12 ugyldige varianter, gyldig, reversal, version ≠ 0)';
END $kerne$;

-- 2) Klassifikatoren med syntetiske kandidatrækker (egne score_raw, uafrundede).
DO $klassifikator$
DECLARE
  v_src jsonb:=pg_temp.pp_source(-6520,'11000000-0000-0000-0000-00000006b520');
  v_run uuid; v_cfg jsonb:='{"autoCutoff":0.9,"controlMargin":0.05,"topK":3,"reviewCutoff":0.7}'; v_r uuid; v_r2 uuid;
  X bigint:=-652001; Y bigint:=-652002; Z bigint:=-652003;
  v_p uuid[]:='{}'; v_i int; v_o jsonb; v_m uuid; v_obs uuid;
BEGIN
  INSERT INTO public.person(id,levende,privat,status) VALUES (X,false,false,'pc'),(Y,false,false,'pc'),(Z,false,false,'pc');
  -- 12 personas på én syntetisk observation (klassifikatoren læser kun kandidatrækkerne)
  v_obs:=(pg_temp.pp_post(v_src,'kl',-652009)->>'observation')::uuid;
  FOR v_i IN 1..12 LOOP
    INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
      VALUES (v_obs,'person',20+v_i,25+v_i,'xxxxx',(v_src->>'run')::uuid) RETURNING id INTO v_m;
    v_p:=v_p||pg_temp.persona(-6520,(v_src->>'run')::uuid,'kl'||v_i,v_m);
  END LOOP;
  v_run:=pg_temp.pc_run(-6520,v_cfg,'kl');
  -- (a) egen 0,95 med birth, ingen konkurrent
  PERFORM pg_temp.pc_cand(v_run,v_p[1],X,1,jsonb_build_array(pg_temp.ms(X,0.95,ARRAY['name','birth'])));
  -- (b) samme uden årstal
  PERFORM pg_temp.pc_cand(v_run,v_p[2],X,1,jsonb_build_array(pg_temp.ms(X,0.95,ARRAY['name','sex'])));
  -- (c) anden klynge 0,97
  PERFORM pg_temp.pc_cand(v_run,v_p[3],Y,1,jsonb_build_array(pg_temp.ms(Y,0.97,ARRAY['name','birth'])));
  PERFORM pg_temp.pc_cand(v_run,v_p[3],X,2,jsonb_build_array(pg_temp.ms(X,0.95,ARRAY['name','birth'])));
  -- (d) anden klynge lig egen
  PERFORM pg_temp.pc_cand(v_run,v_p[4],X,1,jsonb_build_array(pg_temp.ms(X,0.95,ARRAY['name','birth'])));
  PERFORM pg_temp.pc_cand(v_run,v_p[4],Y,2,jsonb_build_array(pg_temp.ms(Y,0.95,ARRAY['name'])));
  -- (e) personen findes ikke blandt kandidaterne
  PERFORM pg_temp.pc_cand(v_run,v_p[5],Y,1,jsonb_build_array(pg_temp.ms(Y,0.95,ARRAY['name','birth'])));
  -- (f) klyngepartneren 0,99 i samme række (repræsentant Z), egen 0,70
  PERFORM pg_temp.pc_cand(v_run,v_p[6],Z,1,jsonb_build_array(pg_temp.ms(Z,0.99,ARRAY['name','birth']),pg_temp.ms(X,0.70,ARRAY['name','birth'])));
  -- (f2) klyngepartneren 0,99, egen 0,95 med årstal, ingen anden klynge
  PERFORM pg_temp.pc_cand(v_run,v_p[7],Z,1,jsonb_build_array(pg_temp.ms(Z,0.99,ARRAY['name','birth']),pg_temp.ms(X,0.95,ARRAY['name','birth'])));
  -- (f3) klyngepartneren lig egen
  PERFORM pg_temp.pc_cand(v_run,v_p[8],X,1,jsonb_build_array(pg_temp.ms(X,0.95,ARRAY['name','death']),pg_temp.ms(Z,0.95,ARRAY['name'])));
  -- (g) margin lige under controlMargin (0,95 − 0,9001 = 0,0499)
  PERFORM pg_temp.pc_cand(v_run,v_p[9],X,1,jsonb_build_array(pg_temp.ms(X,0.95,ARRAY['name','birth'])));
  PERFORM pg_temp.pc_cand(v_run,v_p[9],Y,2,jsonb_build_array(pg_temp.ms(Y,0.9001,ARRAY['name'])));
  -- (g3) margin præcis controlMargin (0,95 − 0,90): enig
  PERFORM pg_temp.pc_cand(v_run,v_p[10],X,1,jsonb_build_array(pg_temp.ms(X,0.95,ARRAY['name','death'])));
  PERFORM pg_temp.pc_cand(v_run,v_p[10],Y,2,jsonb_build_array(pg_temp.ms(Y,0.90,ARRAY['name'])));
  -- (g2) score_raw 0,89996 (afrundet 0,9) med autoCutoff 0,9
  PERFORM pg_temp.pc_cand(v_run,v_p[11],X,1,jsonb_build_array(pg_temp.ms(X,0.89996,ARRAY['name','birth'])));
  -- (u) egen klyngepartner lavere, men anden klynge højere: uenig går forud
  PERFORM pg_temp.pc_cand(v_run,v_p[12],Y,1,jsonb_build_array(pg_temp.ms(Y,0.97,ARRAY['name'])));
  PERFORM pg_temp.pc_cand(v_run,v_p[12],X,2,jsonb_build_array(pg_temp.ms(X,0.95,ARRAY['name','birth']),pg_temp.ms(Z,0.60,ARRAY['name'])));

  v_o:=pg_temp.outcome(v_p[1],v_run,X);
  IF v_o<>jsonb_build_object('outcome','enig','reason',NULL,'own_score',0.95,'competitor_score',NULL,'competitor_person_id',NULL) THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: (a) %',v_o; END IF;
  v_o:=pg_temp.outcome(v_p[2],v_run,X);
  IF v_o->>'outcome' IS DISTINCT FROM 'svag' THEN RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: (b) %',v_o; END IF;
  v_o:=pg_temp.outcome(v_p[3],v_run,X);
  IF v_o->>'outcome' IS DISTINCT FROM 'uenig' OR (v_o->>'competitor_person_id')::bigint<>Y OR (v_o->>'competitor_score')::numeric<>0.97
     OR (v_o->>'own_score')::numeric<>0.95 THEN RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: (c) %',v_o; END IF;
  v_o:=pg_temp.outcome(v_p[4],v_run,X);
  IF v_o->>'outcome' IS DISTINCT FROM 'navnefaelle' OR (v_o->>'competitor_person_id')::bigint<>Y THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: (d) %',v_o; END IF;
  v_o:=pg_temp.outcome(v_p[5],v_run,X);
  IF v_o->>'outcome' IS DISTINCT FROM 'ingen_kandidat' OR v_o->'own_score'<>'null'::jsonb THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: (e) %',v_o; END IF;
  v_o:=pg_temp.outcome(v_p[6],v_run,X);
  IF v_o->>'outcome' IS DISTINCT FROM 'svag' OR v_o->>'reason' IS DISTINCT FROM 'partner_hoejere' OR (v_o->>'own_score')::numeric<>0.70
     OR (v_o->>'competitor_person_id')::bigint<>Z THEN RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: (f) %',v_o; END IF;
  v_o:=pg_temp.outcome(v_p[7],v_run,X);
  IF v_o->>'outcome' IS DISTINCT FROM 'svag' OR v_o->>'reason' IS DISTINCT FROM 'partner_hoejere' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: (f2) %',v_o; END IF;
  v_o:=pg_temp.outcome(v_p[8],v_run,X);
  IF v_o->>'outcome' IS DISTINCT FROM 'svag' OR v_o->>'reason' IS DISTINCT FROM 'partner_hoejere' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: (f3) %',v_o; END IF;
  v_o:=pg_temp.outcome(v_p[9],v_run,X);
  IF v_o->>'outcome' IS DISTINCT FROM 'svag' OR v_o->>'reason' IS DISTINCT FROM 'under_margin' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: (g) %',v_o; END IF;
  v_o:=pg_temp.outcome(v_p[10],v_run,X);
  IF v_o->>'outcome' IS DISTINCT FROM 'enig' OR (v_o->>'competitor_person_id')::bigint<>Y THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: (g3) %',v_o; END IF;
  v_o:=pg_temp.outcome(v_p[11],v_run,X);
  IF v_o->>'outcome' IS DISTINCT FROM 'svag' OR v_o->>'reason' IS DISTINCT FROM 'under_auto' OR (v_o->>'own_score')::numeric<>0.89996 THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: (g2) %',v_o; END IF;
  v_o:=pg_temp.outcome(v_p[12],v_run,X);
  IF v_o->>'outcome' IS DISTINCT FROM 'uenig' OR (v_o->>'competitor_person_id')::bigint<>Y THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: (u) %',v_o; END IF;

  -- (h) konfiguration: uden controlMargin, topK 1, uden autoCutoff, ukendt kørsel; rækker uden member_scores
  v_r:=pg_temp.pc_run(-6520,v_cfg-'controlMargin','h1');
  PERFORM pg_temp.pc_cand(v_r,v_p[1],X,1,jsonb_build_array(pg_temp.ms(X,0.95,ARRAY['name','birth'])));
  IF pg_temp.outcome(v_p[1],v_r,X)<>'{"error":"PUBLICATION_CONTROL_CONFIG_MISSING"}' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: (h) uden controlMargin %',pg_temp.outcome(v_p[1],v_r,X); END IF;
  v_r:=pg_temp.pc_run(-6520,v_cfg||'{"topK":1}','h2');
  PERFORM pg_temp.pc_cand(v_r,v_p[1],X,1,jsonb_build_array(pg_temp.ms(X,0.95,ARRAY['name','birth'])));
  IF pg_temp.outcome(v_p[1],v_r,X)<>'{"error":"PUBLICATION_CONTROL_CONFIG_MISSING"}' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: (h) topK 1'; END IF;
  v_r:=pg_temp.pc_run(-6520,v_cfg-'autoCutoff','h3');
  IF pg_temp.outcome(v_p[1],v_r,X)<>'{"error":"PUBLICATION_CONTROL_CONFIG_MISSING"}' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: (h) uden autoCutoff'; END IF;
  IF pg_temp.outcome(v_p[1],gen_random_uuid(),X)<>'{"error":"PUBLICATION_CONTROL_CONFIG_MISSING"}' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: (h) ukendt kørsel'; END IF;
  v_r2:=pg_temp.pc_run(-6520,v_cfg,'h4');
  INSERT INTO private.source_persona_identity_candidate(run_id,source_persona_id,candidate_person_id,rank,score,tier,basis)
    VALUES (v_r2,v_p[1],X,1,0.95,'auto','{"signals":["name","birth"]}');
  IF pg_temp.outcome(v_p[1],v_r2,X)<>'{"error":"PUBLICATION_CONTROL_CONFIG_MISSING"}' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: (h) række uden member_scores'; END IF;
  RAISE NOTICE 'OK: klassifikatoren (a-g3, partner_hoejere, uafrundet score, konfiguration)';
END $klassifikator$;

-- 3) Stikprøven og red_publication_control / red_publication_control_details.
DO $stikproeve$
DECLARE
  v_src jsonb:=pg_temp.pp_source(-6530,'11000000-0000-0000-0000-00000006b530');
  v_a text:='11000000-0000-0000-0000-00000006b530';
  v_fx jsonb[]:='{}'; v_els jsonb:='{}'; v_batch uuid; v_receipt jsonb; v_i int; v_key text;
  v_bp uuid[]:='{}';  -- B-personas: 1..25 enige, 26..27 svage, 28 'z' uden kandidater, 29 'w' tilbagetrukket binding, 30 'q' ikke-repræsentant
  v_np uuid[]:='{}';  -- ikke-B-personas (v50-lignende), enige
  v_run uuid; v_run2 uuid; v_cfg jsonb:='{"autoCutoff":0.9,"controlMargin":0.05,"topK":3}'; v_ids jsonb:='[]';
  v_ctl jsonb; v_ctl2 jsonb; v_sample uuid[]; v_expected uuid[]; v_det jsonb; v_pd jsonb; v_e jsonb;
  Q bigint:=-653900; R bigint:=-653901; v_nfx jsonb; v_n int; v_res text; v_given uuid[]:='{}'; v_ik uuid; v_iid uuid;
BEGIN
  FOR v_i IN 1..30 LOOP
    v_key:=CASE v_i WHEN 28 THEN 'z' WHEN 29 THEN 'w' WHEN 30 THEN 'q' ELSE 's'||v_i END;
    v_fx:=v_fx||pg_temp.pp_post(v_src,v_key,-653000-v_i);
    v_els:=v_els||jsonb_build_object(pg_temp.el(v_key),pg_temp.pp_payload(v_src,v_fx[v_i]));
  END LOOP;
  v_batch:=pg_temp.pp_begin(v_src,'fixture-pub-a','stik',v_els);
  FOR v_i IN 1..30 LOOP
    v_key:=v_fx[v_i]->>'record_key';
    v_receipt:=pg_temp.pp_apply(v_src,v_batch,pg_temp.el(v_key),v_els->pg_temp.el(v_key));
    v_bp:=v_bp||(v_receipt->>'source_persona_id')::uuid;
  END LOOP;
  FOR v_i IN 1..2 LOOP
    v_nfx:=pg_temp.pp_post(v_src,'n'||v_i,-653100-v_i);
    v_np:=v_np||pg_temp.persona(-6530,(v_src->>'run')::uuid,'1939-v50:n'||v_i,(v_nfx->>'mention')::uuid);
    v_fx:=v_fx||v_nfx;   -- v_fx[31], v_fx[32]
  END LOOP;
  INSERT INTO public.person(id,levende,privat,status) VALUES (Q,false,false,'pc'),(R,false,false,'pc');
  SELECT jsonb_agg(x ORDER BY x) INTO v_ids FROM unnest(v_bp||v_np) x;
  v_run:=pg_temp.pc_run(-6530,v_cfg,'stik',jsonb_build_object('mode','list','persona_ids',v_ids));
  FOR v_i IN 1..25 LOOP
    PERFORM pg_temp.pc_cand(v_run,v_bp[v_i],-653000-v_i,1,jsonb_build_array(pg_temp.ms(-653000-v_i,0.95,ARRAY['name','birth'])));
  END LOOP;
  FOR v_i IN 26..27 LOOP
    PERFORM pg_temp.pc_cand(v_run,v_bp[v_i],-653000-v_i,1,jsonb_build_array(pg_temp.ms(-653000-v_i,0.95,ARRAY['name'])));
  END LOOP;
  -- 'w': binding trukket tilbage efter B → ingen publiceret binding
  PERFORM pg_temp.pc_cand(v_run,v_bp[29],-653029,1,jsonb_build_array(pg_temp.ms(-653029,0.95,ARRAY['name','birth'])));
  UPDATE private.narrative_record_publication SET status='withdrawn' WHERE id=(v_fx[29]->>'binding')::uuid;
  -- 'q': bindingspersonen er ikke repræsentant (Q er), og en konkurrerende klynge R
  PERFORM pg_temp.pc_cand(v_run,v_bp[30],Q,1,jsonb_build_array(pg_temp.ms(Q,0.99,ARRAY['name','birth']),pg_temp.ms(-653030,0.70,ARRAY['name'])));
  PERFORM pg_temp.pc_cand(v_run,v_bp[30],R,2,jsonb_build_array(pg_temp.ms(R,0.60,ARRAY['name'])));
  FOR v_i IN 1..2 LOOP
    PERFORM pg_temp.pc_cand(v_run,v_np[v_i],-653100-v_i,1,jsonb_build_array(pg_temp.ms(-653100-v_i,0.95,ARRAY['name','birth'])));
  END LOOP;
  UPDATE public.person SET staged=true WHERE id=-653002;

  -- uden redaktør: afvist
  IF pg_temp.rpc(NULL,'red_publication_control',v_run)->>'error' IS DISTINCT FROM 'EVIDENCE_ROLE_FORBIDDEN'
     OR pg_temp.rpc(NULL,'red_publication_control_details',v_run)->>'error' IS DISTINCT FROM 'EVIDENCE_ROLE_FORBIDDEN' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: rollevagt'; END IF;

  v_ctl:=pg_temp.rpc(v_a,'red_publication_control',v_run);
  IF v_ctl ? 'error' THEN RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: red_publication_control %',v_ctl; END IF;
  -- hver persona i kørslen præcis én gang, også 'z' uden kandidatrækker
  IF jsonb_array_length(v_ctl->'personas')<>32
     OR (SELECT count(DISTINCT e->>'source_persona_id') FROM jsonb_array_elements(v_ctl->'personas') e)<>32 THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: personaer i kørslen %',jsonb_array_length(v_ctl->'personas'); END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_ctl->'personas') e
              WHERE (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e) k)
                    <>ARRAY['b_binding_id','b_binding_status','binding_id','binding_status','identity_version','in_sample','not_staged','outcome','person_id','reason','source_persona_id']) THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: nøgler'; END IF;
  SELECT e INTO v_e FROM jsonb_array_elements(v_ctl->'personas') e WHERE e->>'source_persona_id'=v_bp[28]::text;
  IF v_e->>'outcome' IS DISTINCT FROM 'ingen_kandidat' OR v_e->>'binding_status'<>'published' OR (v_e->>'person_id')::bigint<>-653028
     OR (v_e->>'in_sample')::boolean THEN RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: z %',v_e; END IF;
  SELECT e INTO v_e FROM jsonb_array_elements(v_ctl->'personas') e WHERE e->>'source_persona_id'=v_bp[29]::text;
  IF v_e->>'binding_status' IS DISTINCT FROM 'none' OR v_e->'outcome'<>'null'::jsonb OR v_e->'binding_id'<>'null'::jsonb
     OR (v_e->>'in_sample')::boolean THEN RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: w %',v_e; END IF;
  -- B-hændelsens binding (samme opslag som finalize's kontrolmængde): 'w' er tilbagetrukket, en normal er published, og en
  -- persona uden B-hændelse (v50-lignende) har ingen
  IF v_e->>'b_binding_id' IS DISTINCT FROM v_fx[29]->>'binding' OR v_e->>'b_binding_status' IS DISTINCT FROM 'withdrawn' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: w B-binding %',v_e; END IF;
  SELECT e INTO v_e FROM jsonb_array_elements(v_ctl->'personas') e WHERE e->>'source_persona_id'=v_bp[3]::text;
  IF v_e->>'binding_status' IS DISTINCT FROM 'published' OR v_e->>'b_binding_status' IS DISTINCT FROM 'published'
     OR v_e->>'b_binding_id' IS DISTINCT FROM v_e->>'binding_id' OR v_e->>'b_binding_id' IS DISTINCT FROM v_fx[3]->>'binding' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: normal B-binding %',v_e; END IF;
  SELECT e INTO v_e FROM jsonb_array_elements(v_ctl->'personas') e WHERE e->>'source_persona_id'=v_np[1]::text;
  IF v_e->'b_binding_id'<>'null'::jsonb OR v_e->'b_binding_status'<>'null'::jsonb THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: v50-lignende B-binding %',v_e; END IF;
  SELECT e INTO v_e FROM jsonb_array_elements(v_ctl->'personas') e WHERE e->>'source_persona_id'=v_bp[30]::text;
  IF v_e->>'outcome' IS DISTINCT FROM 'svag' OR v_e->>'reason' IS DISTINCT FROM 'partner_hoejere' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: q %',v_e; END IF;
  SELECT e INTO v_e FROM jsonb_array_elements(v_ctl->'personas') e WHERE e->>'source_persona_id'=v_bp[2]::text;
  IF (v_e->>'not_staged')::boolean OR v_e->>'binding_id'<>v_fx[2]->>'binding' OR (v_e->>'identity_version')::int<>0 THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: staged/binding %',v_e; END IF;
  SELECT e INTO v_e FROM jsonb_array_elements(v_ctl->'personas') e WHERE e->>'source_persona_id'=v_bp[3]::text;
  IF NOT (v_e->>'not_staged')::boolean THEN RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: not_staged'; END IF;

  -- stikprøven: de 20 laveste hashes blandt de 25 enige B-personas (ikke de svage, ikke v50-lignende)
  SELECT array_agg(e->>'source_persona_id' ORDER BY e->>'source_persona_id')::uuid[] INTO v_sample
    FROM jsonb_array_elements(v_ctl->'personas') e WHERE (e->>'in_sample')::boolean;
  SELECT array_agg(x.id ORDER BY x.id) INTO v_expected FROM (
    SELECT sp.id FROM private.source_persona sp, private.source_persona_identity_candidate_run r
     WHERE r.id=v_run AND sp.id=ANY(v_bp[1:25])
     ORDER BY encode(extensions.digest(convert_to('publication-sample-v1:'||r.input_sha256||':'||r.config_sha256||':'||sp.persona_key,'UTF8'),'sha256'),'hex') COLLATE "C"
     LIMIT 20) x;
  IF cardinality(v_sample)<>20 OR v_sample<>v_expected THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: stikprøven (% stk.)',cardinality(v_sample); END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_ctl->'personas') e WHERE (e->>'in_sample')::boolean AND e->>'outcome'<>'enig') THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: stikprøve med ikke-enig'; END IF;
  -- in_sample-funktionen stemmer med RPC'en for hver persona (false for ikke-enige og ikke-B)
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_ctl->'personas') e
              WHERE private.publication_control_in_sample((e->>'source_persona_id')::uuid,v_run)<>(e->>'in_sample')::boolean) THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: in_sample ≠ RPC'; END IF;
  IF private.publication_control_in_sample(v_np[1],v_run) OR private.publication_control_in_sample(v_bp[26],v_run) THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: ikke-B/svag i stikprøven'; END IF;
  -- deterministisk
  v_ctl2:=pg_temp.rpc(v_a,'red_publication_control',v_run);
  IF v_ctl2<>v_ctl THEN RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: ikke deterministisk'; END IF;

  -- 10 af de enige får identitet med publication_binding (5 i stikprøven, 5 udenfor); stikprøven er den samme
  FOR v_i IN 1..25 LOOP
    IF (v_bp[v_i]=ANY(v_sample) AND cardinality(ARRAY(SELECT unnest(v_given) INTERSECT SELECT unnest(v_sample)))<5)
       OR (NOT v_bp[v_i]=ANY(v_sample) AND cardinality(ARRAY(SELECT unnest(v_given) EXCEPT SELECT unnest(v_sample)))<5) THEN
      v_res:=pg_temp.kerne(v_a,v_bp[v_i],-653000-v_i,0,'accepted',
        jsonb_build_object('authority','narrative_record_publication','binding_id',v_fx[v_i]->>'binding'),'publication_binding');
      IF v_res<>'OK' THEN RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: publication_binding for B-persona %: %',v_i,v_res; END IF;
      v_given:=v_given||v_bp[v_i];
    END IF;
  END LOOP;
  IF cardinality(v_given)<>10 THEN RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: %/10 identiteter',cardinality(v_given); END IF;
  v_ctl2:=pg_temp.rpc(v_a,'red_publication_control',v_run);
  SELECT array_agg(e->>'source_persona_id' ORDER BY e->>'source_persona_id')::uuid[] INTO v_expected
    FROM jsonb_array_elements(v_ctl2->'personas') e WHERE (e->>'in_sample')::boolean;
  IF v_expected<>v_sample
     OR EXISTS (SELECT 1 FROM unnest(v_sample) s WHERE NOT private.publication_control_in_sample(s,v_run)) THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: stikprøven flyttede sig efter identiteter'; END IF;
  IF (SELECT count(*) FROM jsonb_array_elements(v_ctl2->'personas') e WHERE (e->>'identity_version')::int=1)<>10 THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: identity_version'; END IF;

  -- færre end 20 enige → alle enige er med (ny kørsel: kandidatrækker er append-only; B-personas 1-10 uden årstal)
  v_run2:=pg_temp.pc_run(-6530,v_cfg,'stik-15',jsonb_build_object('mode','list','persona_ids',v_ids));
  FOR v_i IN 1..25 LOOP
    PERFORM pg_temp.pc_cand(v_run2,v_bp[v_i],-653000-v_i,1,
      jsonb_build_array(pg_temp.ms(-653000-v_i,0.95,CASE WHEN v_i<=10 THEN ARRAY['name'] ELSE ARRAY['name','birth'] END)));
  END LOOP;
  FOR v_i IN 1..2 LOOP
    PERFORM pg_temp.pc_cand(v_run2,v_np[v_i],-653100-v_i,1,jsonb_build_array(pg_temp.ms(-653100-v_i,0.95,ARRAY['name','birth'])));
  END LOOP;
  v_ctl2:=pg_temp.rpc(v_a,'red_publication_control',v_run2);
  IF (SELECT count(*) FROM jsonb_array_elements(v_ctl2->'personas') e WHERE (e->>'in_sample')::boolean)<>15
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_ctl2->'personas') e
                 WHERE e->>'outcome'='enig' AND e->>'source_persona_id'<>ALL(ARRAY[v_np[1]::text,v_np[2]::text])
                   AND NOT (e->>'in_sample')::boolean) THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: færre end 20 enige'; END IF;
  RAISE NOTICE 'OK: stikprøven (20 af 25, kun enige B-personas, deterministisk, uafhængig af identiteter; færre end 20 → alle)';

  -- details: bindingspersonen med også når den ikke er repræsentant ('q') og ved ingen_kandidat ('z')
  -- titel: afklaret titel-faktum (matcherens kilde) og et ikke-afklaret, der ikke må vises
  WITH f AS (INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',-653030,'titel') RETURNING id),
       a AS (INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) SELECT 'fact',f.id,'Syntetisk titel' FROM f RETURNING id,target_id)
  INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status) SELECT 'fact',a.target_id,a.id,'afklaret' FROM a;
  WITH f AS (INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',-653030,'titel') RETURNING id),
       a AS (INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) SELECT 'fact',f.id,'Omstridt titel' FROM f RETURNING id,target_id)
  INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status) SELECT 'fact',a.target_id,a.id,'omstridt' FROM a;
  -- personaens foreslåede navn (proposed fortolkning med sin observation)
  v_ik:=gen_random_uuid(); v_iid:=gen_random_uuid();
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,predicate,value,
    schema_version,derivation_kind,confidence,status,method,extraction_run_id)
  VALUES (v_iid,v_ik,1,-6530,v_bp[30],'property','person.name','"Syntetisk foreslået"','t','model_inference',0.9,'proposed','t',
          (v_src->>'run')::uuid);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_iid,(v_fx[30]->>'observation')::uuid,'supporting',1);
  -- visningscachen sat syntetisk EFTER faktaene (deres trigger regenererer cachen)
  UPDATE public.person SET visning_navn='Syntetisk Q-binding', visning_foedt='1800', visning_doed='1870' WHERE id=-653030;
  v_det:=pg_temp.rpc(v_a,'red_publication_control_details',v_run);
  IF v_det ? 'error' THEN RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: details %',v_det->>'error'; END IF;
  SELECT e INTO v_pd FROM jsonb_array_elements(v_det->'personas') e WHERE e->>'source_persona_id'=v_bp[30]::text;
  IF v_pd IS NULL OR NOT (v_pd ? 'proposed') OR NOT (v_pd->'proposed' ?& ARRAY['name','birth','death'])
     OR v_pd->'outcome'->>'outcome' IS DISTINCT FROM 'svag' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: details q-persona'; END IF;
  SELECT e INTO v_e FROM jsonb_array_elements(v_pd->'persons') e WHERE (e->>'person_id')::bigint=-653030;
  IF v_e->>'role' IS DISTINCT FROM 'binding' OR v_e->>'navn' IS DISTINCT FROM 'Syntetisk Q-binding' OR v_e->>'foedt'<>'1800'
     OR v_e->>'doed'<>'1870' OR (v_e->>'score_raw')::numeric<>0.70 OR NOT (v_e->'record_labels' @> '["Fixture q"]')
     OR v_e->'titel'<>'["Syntetisk titel"]'::jsonb OR v_pd->'proposed'->>'name' IS DISTINCT FROM 'Syntetisk foreslået' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: details bindingsperson %',v_e; END IF;
  IF (SELECT array_agg((e->>'person_id')::bigint ORDER BY (e->>'person_id')::bigint) FROM jsonb_array_elements(v_pd->'persons') e)
     <>ARRAY[R,Q,-653030]::bigint[]   -- stigende id
     OR (SELECT e->>'role' FROM jsonb_array_elements(v_pd->'persons') e WHERE (e->>'person_id')::bigint=Q)<>'own_cluster'
     OR (SELECT e->>'role' FROM jsonb_array_elements(v_pd->'persons') e WHERE (e->>'person_id')::bigint=R)<>'competitor' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: details klynger'; END IF;
  SELECT e INTO v_pd FROM jsonb_array_elements(v_det->'personas') e WHERE e->>'source_persona_id'=v_bp[28]::text;
  IF v_pd->'outcome'->>'outcome' IS DISTINCT FROM 'ingen_kandidat'
     OR jsonb_array_length(v_pd->'persons')<>1 OR (v_pd->'persons'->0->>'person_id')::bigint<>-653028
     OR v_pd->'persons'->0->>'role'<>'binding' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: details ingen_kandidat %',v_pd; END IF;
  IF jsonb_array_length(v_det->'personas')<>32 THEN RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: details antal'; END IF;
  -- detaljerne bærer samme B-binding som oversigten
  SELECT e INTO v_pd FROM jsonb_array_elements(v_det->'personas') e WHERE e->>'source_persona_id'=v_bp[29]::text;
  IF v_pd->>'binding_status' IS DISTINCT FROM 'none' OR v_pd->>'b_binding_status' IS DISTINCT FROM 'withdrawn'
     OR v_pd->>'b_binding_id' IS DISTINCT FROM v_fx[29]->>'binding' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: details w B-binding %',v_pd; END IF;
  SELECT e INTO v_pd FROM jsonb_array_elements(v_det->'personas') e WHERE e->>'source_persona_id'=v_bp[3]::text;
  IF v_pd->>'binding_status' IS DISTINCT FROM 'published' OR v_pd->>'b_binding_status' IS DISTINCT FROM 'published'
     OR v_pd->>'b_binding_id' IS DISTINCT FROM v_fx[3]->>'binding' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: details normal B-binding %',v_pd; END IF;
  RAISE NOTICE 'OK: red_publication_control og red_publication_control_details';
END $stikproeve$;

-- 4) details: bindingspersonen filtreret bort af generatoren (ingen member_scores-post); dens samme_som-partner — også
-- transitivt i en komponent med tre medlemmer — er egen klynge, ikke konkurrent (spec §4.3 pkt. 2, #248).
DO $komponent$
DECLARE
  v_src jsonb:=pg_temp.pp_source(-6540,'11000000-0000-0000-0000-00000006b540');
  v_a text:='11000000-0000-0000-0000-00000006b540';
  v_f1 jsonb; v_f2 jsonb; v_p1 uuid; v_p2 uuid; v_run uuid; v_det jsonb; v_pd jsonb;
  B1 bigint:=-654001; P1 bigint:=-654011; B2 bigint:=-654002; K21 bigint:=-654021; K22 bigint:=-654022; C bigint:=-654030;
  v_roles jsonb;
BEGIN
  v_f1:=pg_temp.pp_post(v_src,'c1',B1); v_f2:=pg_temp.pp_post(v_src,'c2',B2);
  INSERT INTO public.person(id,levende,privat,status) VALUES (P1,false,false,'pc'),(K21,false,false,'pc'),(K22,false,false,'pc'),(C,false,false,'pc');
  -- c1: B1 ~ P1 (direkte); c2: B2 ~ K21 ~ K22 (K22 kun transitivt, relationen i den anden retning)
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES
    ('person',B1,'person',P1,'samme_som'),('person',B2,'person',K21,'samme_som'),('person',K22,'person',K21,'samme_som');
  v_p1:=pg_temp.persona(-6540,(v_src->>'run')::uuid,'1939:c1',(v_f1->>'mention')::uuid);
  v_p2:=pg_temp.persona(-6540,(v_src->>'run')::uuid,'1939:c2',(v_f2->>'mention')::uuid);
  v_run:=pg_temp.pc_run(-6540,'{"autoCutoff":0.9,"controlMargin":0.05,"topK":3}','komp');
  PERFORM pg_temp.pc_cand(v_run,v_p1,P1,1,jsonb_build_array(pg_temp.ms(P1,0.99,ARRAY['name','birth'])));
  PERFORM pg_temp.pc_cand(v_run,v_p1,C,2,jsonb_build_array(pg_temp.ms(C,0.50,ARRAY['name'])));
  PERFORM pg_temp.pc_cand(v_run,v_p2,K22,1,jsonb_build_array(pg_temp.ms(K22,0.99,ARRAY['name','birth'])));
  PERFORM pg_temp.pc_cand(v_run,v_p2,C,2,jsonb_build_array(pg_temp.ms(C,0.50,ARRAY['name'])));
  v_det:=pg_temp.rpc(v_a,'red_publication_control_details',v_run);
  IF v_det ? 'error' THEN RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: details %',v_det->>'error'; END IF;
  SELECT e INTO v_pd FROM jsonb_array_elements(v_det->'personas') e WHERE e->>'source_persona_id'=v_p1::text;
  SELECT jsonb_object_agg(e->>'person_id',e->>'role') INTO v_roles FROM jsonb_array_elements(v_pd->'persons') e;
  IF v_roles<>jsonb_build_object(B1::text,'binding',P1::text,'own_cluster',C::text,'competitor')
     OR v_pd->'outcome'->>'outcome' IS DISTINCT FROM 'ingen_kandidat' THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: direkte partner %',v_roles; END IF;
  SELECT e INTO v_pd FROM jsonb_array_elements(v_det->'personas') e WHERE e->>'source_persona_id'=v_p2::text;
  SELECT jsonb_object_agg(e->>'person_id',e->>'role') INTO v_roles FROM jsonb_array_elements(v_pd->'persons') e;
  IF v_roles<>jsonb_build_object(B2::text,'binding',K22::text,'own_cluster',C::text,'competitor') THEN
    RAISE EXCEPTION 'PUBLICATION_CONTROL_TEST_FAILED: transitiv komponent %',v_roles; END IF;
  RAISE NOTICE 'OK: details bruger bindingspersonens samme_som-komponent (direkte og transitivt)';
END $komponent$;

ROLLBACK;
