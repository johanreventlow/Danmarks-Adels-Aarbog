\set ON_ERROR_STOP on
-- Trin 6m del 2 (blok 6m-a): red_ret_forslag skriver en ny proposed-version af et faktaforslag med en menneskeligt læst
-- værdi, og den udskudte kontrol private.kontroller_forslag_binding_v1 afviser ved COMMIT en genåbning af et bundet
-- accepteret forslag, der ikke afgøres og genbindes i samme transaktion. Alt syntetisk; rulles tilbage, så filen kan
-- køres flere gange mod samme base. Fixturen er paastand-rettelsens (persona med accepteret identitet, fakta, binding).
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql

-- Et afklaret tekstfaktum med én påstand citeret af p_source.
CREATE FUNCTION pg_temp.fl_fakta(p_person bigint,p_faktatype text,p_value text,p_source bigint) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE v_fact bigint; v_a bigint;
BEGIN
  INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',p_person,p_faktatype) RETURNING id INTO v_fact;
  INSERT INTO assertion(target_type,target_id,vaerdi_tekst,uforanderlig) VALUES ('fact',v_fact,p_value,true)
    RETURNING id INTO v_a;
  INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_fact,v_a,'afklaret');
  INSERT INTO citation(assertion_id,source_id,citat_tekst,side) VALUES (v_a,p_source,'fl','3');
  RETURN v_a;
END $$;

-- Et forslag (version 1, proposed) fra postens hovedperson-persona.
CREATE FUNCTION pg_temp.fl_forslag(p_source bigint,p_post jsonb,p_run uuid,p_predicate text,p_value jsonb)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_int uuid:=gen_random_uuid();
BEGIN
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
    predicate,value,schema_version,derivation_kind,confidence,status,method,model_version,prompt_version,extraction_run_id)
    VALUES (v_int,gen_random_uuid(),1,p_source,(p_post->>'principal')::uuid,'property',p_predicate,p_value,
      '1.0','model_inference',0.7,'proposed','fixture','m-6ma','p-6ma',p_run);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_int,(p_post->'clauses'->>0)::uuid,'supporting',1),(v_int,(p_post->'clauses'->>1)::uuid,'context',2);
  RETURN v_int;
END $$;

-- Afgør et forslag som redaktør; returnerer den nye version.
CREATE FUNCTION pg_temp.fl_afgoer(p_actor uuid,p_int uuid,p_status text,p_basis text DEFAULT 'forslag-laesning-test')
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_version integer; v_new uuid;
BEGIN
  SELECT version INTO v_version FROM private.interpretation WHERE id=p_int;
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_new:=public.red_decide_interpretation(p_int,v_version,p_status,jsonb_build_object('basis',p_basis));
  RESET ROLE;
  RETURN v_new;
END $$;

-- Binder et accepteret forslag til en påstand gennem preview + batch.
CREATE FUNCTION pg_temp.fl_bind(p_int uuid,p_a bigint) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE items jsonb; pv jsonb; v_prom uuid;
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',p_int::text,'target_type','assertion','target_id',p_a));
  pv:=public.red_preview_interpretation_promotions(items);
  PERFORM public.red_promote_interpretations_batch(items,pv->>'preview_hash');
  RESET ROLE;
  PERFORM set_config('app.change_set_id','',true);
  SELECT id INTO v_prom FROM private.interpretation_promotion
   WHERE interpretation_id=p_int AND target_type='assertion' AND target_id=p_a;
  IF v_prom IS NULL THEN RAISE EXCEPTION 'FORSLAG_TEST_FIXTURE: ingen promotion'; END IF;
  RETURN v_prom;
END $$;

-- Gyldig læsningsevidens.
CREATE FUNCTION pg_temp.fl_ev() RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('basis','menneske-laesning-v1','manifest_a_sha256',repeat('a',64),'ark_sha256',repeat('b',64),
    'ref','A 7','svar','FORSLAG_FEJL','billede','bekraefter')
$$;

-- red_ret_forslag som authenticated (claim sættes af kalderen); returnerer kvitteringen.
CREATE FUNCTION pg_temp.fl_ret(p_int uuid,p_version integer,p_vaerdi text,p_ev jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  SET LOCAL ROLE authenticated;
  r:=public.red_ret_forslag(p_int,p_version,p_vaerdi,p_ev);
  RESET ROLE;
  RETURN r;
END $$;

-- Forventet fejl fra red_ret_forslag, kaldt som p_role. Fejlen ruller kaldets delttransaktion tilbage.
CREATE FUNCTION pg_temp.fl_fejl(p_token text,p_int uuid,p_version integer,p_vaerdi text,p_ev jsonb,
  p_role text DEFAULT 'authenticated') RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE format('SET LOCAL ROLE %I',p_role);
    PERFORM public.red_ret_forslag(p_int,p_version,p_vaerdi,p_ev);
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    IF SQLERRM IS NULL OR SQLERRM NOT LIKE p_token||'%' THEN
      RAISE EXCEPTION 'FORSLAG_TEST_WRONG_ERROR: expected % got %',p_token,SQLERRM;
    END IF;
    RETURN;
  END;
  RESET ROLE;
  RAISE EXCEPTION 'FORSLAG_TEST_NO_ERROR: expected %',p_token;
END $$;

-- 1) Katalog: RPC'en kun for authenticated; triggerfunktionen privat og SECURITY DEFINER; triggeren udskudt.
DO $katalog$
DECLARE f text:='public.red_ret_forslag(uuid,integer,text,jsonb)'; t text:='private.kontroller_forslag_binding_v1()';
BEGIN
  IF to_regprocedure(f) IS NULL OR NOT (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure(f))
     OR has_function_privilege('anon',f,'EXECUTE') OR NOT has_function_privilege('authenticated',f,'EXECUTE') THEN
    RAISE EXCEPTION 'FORSLAG_TEST_RPC_ACL';
  END IF;
  IF to_regprocedure(t) IS NULL OR NOT (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure(t))
     OR NOT EXISTS (SELECT 1 FROM pg_proc p, unnest(p.proconfig) c WHERE p.oid=to_regprocedure(t)
                     AND c='search_path=pg_catalog, public, private')
     OR has_function_privilege('anon',t,'EXECUTE') OR has_function_privilege('authenticated',t,'EXECUTE')
     OR has_function_privilege('service_role',t,'EXECUTE') THEN
    RAISE EXCEPTION 'FORSLAG_TEST_TRIGGERFUNKTION';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger g WHERE g.tgrelid='private.interpretation'::regclass
                   AND g.tgname='interpretation_forslag_binding' AND g.tgconstraint<>0 AND g.tgdeferrable
                   AND g.tginitdeferred AND g.tgfoid=to_regprocedure(t)) THEN
    RAISE EXCEPTION 'FORSLAG_TEST_TRIGGER';
  END IF;
END $katalog$;

-- 2) Reglerne, en vellykket læsning, genåbninger og den udskudte kontrol.
DO $laesning$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-0000006a0a01'; v_medlem uuid:='11000000-0000-0000-0000-0000006a0a02';
  v_p bigint:=-6801; v_s bigint:=-6801; m jsonb; v_post jsonb; v_run uuid; v_run2 uuid:=gen_random_uuid(); m2 jsonb;
  i_titel uuid; i_afvist uuid; i_afvist2 uuid; i_super uuid; i_rel uuid; i_obj uuid;
  a_bund bigint; i_bund uuid; i_bund2 uuid; a_ny bigint; i_ny uuid; i_ny2 uuid; a_alene bigint; i_alene uuid;
  i_alene2 uuid; v_prom uuid; v_prom2 uuid;
  r jsonb; v2 private.interpretation%ROWTYPE; v1 private.interpretation%ROWTYPE; ev jsonb:=pg_temp.fl_ev();
  v_new uuid; v_err text; v_ver integer; k text;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO auth.users(id,email) VALUES (v_medlem,'medlem@6ma.invalid');
  INSERT INTO profiles(id,rolle,navn,email) VALUES (v_medlem,'medlem','Medlem 6ma','medlem@6ma.invalid');
  INSERT INTO person(id,levende,privat,status) VALUES (v_p,false,false,'fl');
  m:=pg_temp.f5b_source(v_s);
  v_run:=(m->>'run')::uuid;
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
    VALUES (v_run2,v_s,'6ma-ceremoni','fixture','fixture','fixture',repeat('5',64),'{}');
  m2:=pg_temp.f5b_source(-6802);
  v_post:=pg_temp.f5b_post(v_s,m,'P6801','Anna Alfa. Kammerherre.',ARRAY['Anna Alfa.','Kammerherre.'],v_p,v_actor);
  PERFORM pg_temp.f2a_event_for_state((v_post->>'principal')::uuid);

  i_titel:=pg_temp.fl_forslag(v_s,v_post,v_run,'person.title',to_jsonb('Overhofmarskal'::text));
  i_afvist:=pg_temp.fl_forslag(v_s,v_post,v_run,'person.title',to_jsonb('Gehejmeråd'::text));
  i_super:=pg_temp.fl_forslag(v_s,v_post,v_run,'person.title',to_jsonb('Etatsråd'::text));
  i_obj:=pg_temp.fl_forslag(v_s,v_post,v_run,'person.title','{"raw":"Etatsråd"}'::jsonb);
  i_rel:=(pg_temp.f5b_claim(v_s,m,'relation.marriage',(v_post->'clauses'->>1)::uuid,'Kammerherre.')->>'id')::uuid;
  a_bund:=pg_temp.fl_fakta(v_p,'titel','Kammerjunker',v_s);
  i_bund:=pg_temp.fl_forslag(v_s,v_post,v_run,'person.title',to_jsonb('Kammerjunker'::text));
  a_ny:=pg_temp.fl_fakta(v_p,'titel','Kancelliråd',v_s);
  i_ny:=pg_temp.fl_forslag(v_s,v_post,v_run,'person.title',to_jsonb('Kancelliråd'::text));
  a_alene:=pg_temp.fl_fakta(v_p,'titel','Justitsråd',v_s);
  i_alene:=pg_temp.fl_forslag(v_s,v_post,v_run,'person.title',to_jsonb('Justitsråd'::text));
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  i_afvist2:=pg_temp.fl_afgoer(v_actor,i_afvist,'rejected');
  i_super:=pg_temp.fl_afgoer(v_actor,i_super,'superseded');
  i_bund2:=pg_temp.fl_afgoer(v_actor,i_bund,'accepted');
  v_prom:=pg_temp.fl_bind(i_bund2,a_bund);
  i_ny2:=pg_temp.fl_afgoer(v_actor,i_ny,'accepted');
  PERFORM pg_temp.fl_bind(i_ny2,a_ny);
  i_alene2:=pg_temp.fl_afgoer(v_actor,i_alene,'accepted');
  PERFORM pg_temp.fl_bind(i_alene2,a_alene);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF NOT private.assertion_binding_current(v_prom) THEN RAISE EXCEPTION 'FORSLAG_TEST_FIXTURE: binding ugyldig'; END IF;

  -- Regel 1: rolle (ingen aktør, medlem, anon uden EXECUTE).
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM pg_temp.fl_fejl('EVIDENCE_ROLE_FORBIDDEN',i_titel,1,'Hofmarskal',ev);
  PERFORM set_config('request.jwt.claim.sub',v_medlem::text,true);
  PERFORM pg_temp.fl_fejl('EVIDENCE_ROLE_FORBIDDEN',i_titel,1,'Hofmarskal',ev);
  PERFORM pg_temp.fl_fejl('permission denied',i_titel,1,'Hofmarskal',ev,'anon');
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);

  -- Regel 2: version, findes, konflikt.
  PERFORM pg_temp.fl_fejl('EVIDENCE_EXPECTED_VERSION_REQUIRED',i_titel,0,'Hofmarskal',ev);
  PERFORM pg_temp.fl_fejl('EVIDENCE_EXPECTED_VERSION_REQUIRED',i_titel,NULL,'Hofmarskal',ev);
  PERFORM pg_temp.fl_fejl('EVIDENCE_INTERPRETATION_NOT_FOUND',gen_random_uuid(),1,'Hofmarskal',ev);
  PERFORM pg_temp.fl_fejl('FORSLAG_VERSION_KONFLIKT',i_titel,2,'Hofmarskal',ev);
  -- version 1 af et afgjort forslag: en nyere version findes
  PERFORM pg_temp.fl_fejl('FORSLAG_VERSION_KONFLIKT',i_afvist,1,'Hofmarskal',ev);

  -- Regel 3: status (superseded kan ikke genåbnes).
  PERFORM pg_temp.fl_fejl('FORSLAG_STATUS_UGYLDIG',i_super,2,'Hofmarskal',ev);

  -- Regel 4: art (relation; property med ikke-strengværdi).
  PERFORM pg_temp.fl_fejl('FORSLAG_ART_UGYLDIG',i_rel,1,'Hofmarskal',ev);
  PERFORM pg_temp.fl_fejl('FORSLAG_ART_UGYLDIG',i_obj,1,'Hofmarskal',ev);

  -- Regel 5: værdi (tom, kun blanktegn, NULL; uændret på proposed, også efter blanktegnssamling).
  PERFORM pg_temp.fl_fejl('FORSLAG_VAERDI_TOM',i_titel,1,'',ev);
  PERFORM pg_temp.fl_fejl('FORSLAG_VAERDI_TOM',i_titel,1,E' \n\u00a0\t',ev);
  PERFORM pg_temp.fl_fejl('FORSLAG_VAERDI_TOM',i_titel,1,NULL,ev);
  PERFORM pg_temp.fl_fejl('FORSLAG_UAENDRET',i_titel,1,'Overhofmarskal',ev);
  PERFORM pg_temp.fl_fejl('FORSLAG_UAENDRET',i_titel,1,E' Overhofmarskal\n',ev);

  -- Regel 6: evidensen (kørsels-GUC'en er ikke sat endnu: evidensen afvises før kørslen).
  PERFORM pg_temp.fl_fejl('FORSLAG_EVIDENS_UGYLDIG',i_titel,1,'Hofmarskal',NULL);
  PERFORM pg_temp.fl_fejl('FORSLAG_EVIDENS_UGYLDIG',i_titel,1,'Hofmarskal','[]'::jsonb);
  PERFORM pg_temp.fl_fejl('FORSLAG_EVIDENS_UGYLDIG',i_titel,1,'Hofmarskal','{}'::jsonb);
  FOREACH k IN ARRAY ARRAY['basis','manifest_a_sha256','ark_sha256','ref','svar','billede'] LOOP
    PERFORM pg_temp.fl_fejl('FORSLAG_EVIDENS_UGYLDIG',i_titel,1,'Hofmarskal',ev-k);
  END LOOP;
  PERFORM pg_temp.fl_fejl('FORSLAG_EVIDENS_UGYLDIG',i_titel,1,'Hofmarskal',ev||'{"basis":"kort-6m-a"}');
  PERFORM pg_temp.fl_fejl('FORSLAG_EVIDENS_UGYLDIG',i_titel,1,'Hofmarskal',
    ev||jsonb_build_object('manifest_a_sha256',repeat('a',63)));
  PERFORM pg_temp.fl_fejl('FORSLAG_EVIDENS_UGYLDIG',i_titel,1,'Hofmarskal',
    ev||jsonb_build_object('ark_sha256',repeat('g',64)));
  PERFORM pg_temp.fl_fejl('FORSLAG_EVIDENS_UGYLDIG',i_titel,1,'Hofmarskal',ev||'{"ark_sha256":1}');
  PERFORM pg_temp.fl_fejl('FORSLAG_EVIDENS_UGYLDIG',i_titel,1,'Hofmarskal',ev||'{"ref":"  "}');
  PERFORM pg_temp.fl_fejl('FORSLAG_EVIDENS_UGYLDIG',i_titel,1,'Hofmarskal',ev||'{"ref":7}');
  PERFORM pg_temp.fl_fejl('FORSLAG_EVIDENS_UGYLDIG',i_titel,1,'Hofmarskal',ev||'{"svar":"MODEL_RET"}');
  PERFORM pg_temp.fl_fejl('FORSLAG_EVIDENS_UGYLDIG',i_titel,1,'Hofmarskal',ev||'{"billede":"maaske"}');

  -- Regel 7: kørslen (ikke sat, ugyldig, en anden kildes kørsel, ukendt).
  PERFORM pg_temp.fl_fejl('FORSLAG_KOERSEL_MANGLER',i_titel,1,'Hofmarskal',ev);
  PERFORM set_config('daa.extraction_run_id','ikke-en-uuid',true);
  PERFORM pg_temp.fl_fejl('FORSLAG_KOERSEL_MANGLER',i_titel,1,'Hofmarskal',ev);
  PERFORM set_config('daa.extraction_run_id',m2->>'run',true);
  PERFORM pg_temp.fl_fejl('FORSLAG_KOERSEL_MANGLER',i_titel,1,'Hofmarskal',ev);
  PERFORM set_config('daa.extraction_run_id',gen_random_uuid()::text,true);
  PERFORM pg_temp.fl_fejl('FORSLAG_KOERSEL_MANGLER',i_titel,1,'Hofmarskal',ev);
  PERFORM set_config('daa.extraction_run_id',v_run2::text,true);

  -- Ingen af de afviste kald skrev noget.
  IF (SELECT count(*) FROM private.interpretation i JOIN private.interpretation q ON q.interpretation_key=i.interpretation_key
       WHERE q.id IN (i_titel,i_rel,i_obj))<>3 THEN
    RAISE EXCEPTION 'FORSLAG_TEST_AFVIST_SKREV';
  END IF;

  -- 8) En vellykket læsning af et proposed forslag. Evidensens servernøgler kan ikke forfalskes af kalderen.
  r:=pg_temp.fl_ret(i_titel,1,E' Overhofmarskal\nog  Hofmarskal ',
    ev||'{"foer_bundet":true,"laest_af":"forfalsket","foer_status":"accepted","ekstra":"bevares"}');
  SELECT * INTO v1 FROM private.interpretation WHERE id=i_titel;
  SELECT * INTO v2 FROM private.interpretation WHERE id=(r->>'interpretation_id')::uuid;
  IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(r) x)
       IS DISTINCT FROM ARRAY['foer_status','genaabnet','interpretation_id','version']
     OR (r->>'version')::int<>2 OR r->>'foer_status'<>'proposed' OR r->'genaabnet'<>'false'::jsonb THEN
    RAISE EXCEPTION 'FORSLAG_TEST_KVITTERING: %',r;
  END IF;
  IF v2.version<>2 OR v2.status<>'proposed' OR v2.derivation_kind<>'human_judgement'
     OR v2.method<>'menneske-laesning-v1' OR v2.value<>to_jsonb('Overhofmarskal og Hofmarskal'::text)
     OR v2.supersedes_id<>v1.id OR v2.interpretation_key<>v1.interpretation_key OR v2.source_id<>v1.source_id
     OR v2.source_persona_id IS DISTINCT FROM v1.source_persona_id OR v2.interpretation_kind<>v1.interpretation_kind
     OR v2.predicate<>v1.predicate OR v2.schema_version<>v1.schema_version OR v2.confidence<>v1.confidence
     OR v2.model_version IS DISTINCT FROM v1.model_version OR v2.prompt_version IS DISTINCT FROM v1.prompt_version
     OR v2.extraction_run_id<>v_run2 OR v1.extraction_run_id<>v_run
     OR v2.decided_by IS NOT NULL OR v2.decided_by_name IS NOT NULL OR v2.decided_at IS NOT NULL THEN
    RAISE EXCEPTION 'FORSLAG_TEST_V2: %',to_jsonb(v2);
  END IF;
  IF v2.decision_evidence->>'basis'<>'menneske-laesning-v1' OR v2.decision_evidence->>'manifest_a_sha256'<>repeat('a',64)
     OR v2.decision_evidence->>'ark_sha256'<>repeat('b',64) OR v2.decision_evidence->>'ref'<>'A 7'
     OR v2.decision_evidence->>'svar'<>'FORSLAG_FEJL' OR v2.decision_evidence->>'billede'<>'bekraefter'
     OR v2.decision_evidence->>'laest_af'<>v_actor::text OR v2.decision_evidence->>'laest_af_navn'<>'5b fixture'
     OR v2.decision_evidence->>'laest_at' !~ '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$'
     OR v2.decision_evidence->'foer_status'<>'"proposed"'::jsonb OR v2.decision_evidence->'foer_version'<>'1'::jsonb
     OR v2.decision_evidence->'foer_bundet'<>'false'::jsonb OR v2.decision_evidence->>'ekstra'<>'bevares' THEN
    RAISE EXCEPTION 'FORSLAG_TEST_EVIDENS: %',v2.decision_evidence;
  END IF;
  IF (SELECT array_agg(observation_id::text||'|'||evidence_role||'|'||ordinal ORDER BY ordinal)
        FROM private.interpretation_observation WHERE interpretation_id=v2.id)
     IS DISTINCT FROM (SELECT array_agg(observation_id::text||'|'||evidence_role||'|'||ordinal ORDER BY ordinal)
        FROM private.interpretation_observation WHERE interpretation_id=v1.id)
     OR (SELECT count(*) FROM private.interpretation_observation WHERE interpretation_id=v2.id)<>2 THEN
    RAISE EXCEPTION 'FORSLAG_TEST_OBSERVATIONER';
  END IF;
  IF v1.value<>to_jsonb('Overhofmarskal'::text) OR v1.status<>'proposed' OR v1.method<>'fixture'
     OR (SELECT id FROM private.interpretation_current WHERE interpretation_key=v1.interpretation_key)<>v2.id THEN
    RAISE EXCEPTION 'FORSLAG_TEST_V1_ELLER_CURRENT';
  END IF;
  -- Anden kørsel med samme forventede version afvises; versionen er stadig 2.
  PERFORM pg_temp.fl_fejl('FORSLAG_VERSION_KONFLIKT',i_titel,1,'Overhofmarskal og Hofmarskal',ev);
  -- Den ubundne læsning må gerne stå alene ved COMMIT.
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  -- red_decide_interpretation kan ikke efterligne læsningen.
  BEGIN
    PERFORM pg_temp.fl_afgoer(v_actor,v2.id,'accepted','menneske-laesning-v1');
    RAISE EXCEPTION 'FORSLAG_TEST_NO_ERROR: reserveret grundlag';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    IF SQLERRM NOT LIKE 'EVIDENCE_BASIS_RESERVED: menneske-laesning-v1%' THEN
      RAISE EXCEPTION 'FORSLAG_TEST_RESERVERET: %',SQLERRM;
    END IF;
  END;

  -- 9) Genåbning af et afvist forslag med uændret værdi.
  r:=pg_temp.fl_ret(i_afvist2,2,'Gehejmeråd',ev);
  SELECT * INTO v2 FROM private.interpretation WHERE id=(r->>'interpretation_id')::uuid;
  IF r->'genaabnet'<>'true'::jsonb OR r->>'foer_status'<>'rejected' OR (r->>'version')::int<>3
     OR v2.status<>'proposed' OR v2.value<>to_jsonb('Gehejmeråd'::text) OR v2.supersedes_id<>i_afvist2
     OR v2.decision_evidence->'foer_status'<>'"rejected"'::jsonb OR v2.decision_evidence->'foer_bundet'<>'false'::jsonb THEN
    RAISE EXCEPTION 'FORSLAG_TEST_GENAABN_AFVIST: % %',r,to_jsonb(v2);
  END IF;
  -- Nu er den proposed igen: samme værdi er ikke længere en genåbning.
  PERFORM pg_temp.fl_fejl('FORSLAG_UAENDRET',v2.id,3,'Gehejmeråd',ev);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;

  -- 10) Et bundet accepteret forslag genåbnet alene: kaldt som authenticated med redaktør-claim afviser den udskudte
  -- kontrol ved SET CONSTRAINTS (som ved COMMIT) med FORSLAG_BINDING_TABT, ikke permission denied.
  BEGIN
    SET LOCAL ROLE authenticated;
    r:=public.red_ret_forslag(i_bund2,2,'Kammerjunker',ev);
    RESET ROLE;
    IF r->'genaabnet'<>'true'::jsonb OR r->>'foer_status'<>'accepted'
       OR (SELECT decision_evidence->'foer_bundet' FROM private.interpretation WHERE id=(r->>'interpretation_id')::uuid)
          <>'true'::jsonb THEN
      RAISE EXCEPTION 'FORSLAG_TEST_FOER_BUNDET: %',r;
    END IF;
    SET LOCAL ROLE authenticated;
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE EXCEPTION 'FORSLAG_TEST_NO_ERROR: binding tabt';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    IF SQLERRM NOT LIKE 'FORSLAG_BINDING_TABT%' THEN RAISE EXCEPTION 'FORSLAG_TEST_BINDING_TABT: %',SQLERRM; END IF;
  END;
  SET CONSTRAINTS ALL DEFERRED;
  -- Også genåbnet og accepteret igen, men uden genbinding: bindingen er tabt.
  BEGIN
    r:=pg_temp.fl_ret(i_bund2,2,'Kammerjunker',ev);
    PERFORM pg_temp.fl_afgoer(v_actor,(r->>'interpretation_id')::uuid,'accepted','kort-6m-a');
    SET LOCAL ROLE authenticated;
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE EXCEPTION 'FORSLAG_TEST_NO_ERROR: accepteret uden genbinding';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    IF SQLERRM NOT LIKE 'FORSLAG_BINDING_TABT%' THEN RAISE EXCEPTION 'FORSLAG_TEST_UDEN_GENBINDING: %',SQLERRM; END IF;
  END;
  SET CONSTRAINTS ALL DEFERRED;
  IF (SELECT id FROM private.interpretation_current WHERE interpretation_key=
       (SELECT interpretation_key FROM private.interpretation WHERE id=i_bund2))<>i_bund2
     OR NOT private.assertion_binding_current(v_prom) THEN
    RAISE EXCEPTION 'FORSLAG_TEST_TILBAGERULNING';
  END IF;

  -- 11) Samme genåbning efterfulgt af afgørelse og genbinding i samme transaktion: ingen fejl.
  r:=pg_temp.fl_ret(i_bund2,2,'Kammerjunker',ev);
  v_new:=pg_temp.fl_afgoer(v_actor,(r->>'interpretation_id')::uuid,'accepted','kort-6m-a');
  v_prom2:=pg_temp.fl_bind(v_new,a_bund);
  SET LOCAL ROLE authenticated;
  SET CONSTRAINTS ALL IMMEDIATE;
  RESET ROLE;
  SET CONSTRAINTS ALL DEFERRED;
  IF NOT private.assertion_binding_current(v_prom2) OR private.assertion_binding_current(v_prom)
     OR (SELECT version FROM private.interpretation WHERE id=v_new)<>4 THEN
    RAISE EXCEPTION 'FORSLAG_TEST_GENBINDING';
  END IF;

  -- 12) Ceremoniens kæde med ny værdi: læsning, påstandsrettelse (bogen_har_ret), afgørelse og genbinding.
  r:=pg_temp.fl_ret(i_ny2,2,'Konferensråd',ev);
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_ret_paastand(a_ny,
    (SELECT jsonb_build_object('fact_id',f.id,'faktatype',f.faktatype,'vaerdi_tekst',a.vaerdi_tekst,'date_raw',a.date_raw,
              'valgt_assertion_id',c.valgt_assertion_id,'citation_sources',jsonb_build_array(v_s))
       FROM assertion a JOIN fact f ON f.id=a.target_id
       LEFT JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id WHERE a.id=a_ny),
    'bogen_har_ret',(r->>'interpretation_id')::uuid,NULL);
  RESET ROLE;
  PERFORM set_config('app.change_set_id','',true);
  v_new:=pg_temp.fl_afgoer(v_actor,(r->>'interpretation_id')::uuid,'accepted','kort-6m-a');
  v_prom2:=pg_temp.fl_bind(v_new,a_ny);
  SET LOCAL ROLE authenticated;
  SET CONSTRAINTS ALL IMMEDIATE;
  RESET ROLE;
  SET CONSTRAINTS ALL DEFERRED;
  IF (SELECT vaerdi_tekst FROM assertion WHERE id=a_ny)<>'Konferensråd' OR NOT private.assertion_binding_current(v_prom2) THEN
    RAISE EXCEPTION 'FORSLAG_TEST_KAEDE';
  END IF;

  -- 13) Et andet bundet forslag genåbnet alene i samme transaktion som en gyldig kæde: kontrollen gælder pr. nøgle.
  BEGIN
    r:=pg_temp.fl_ret(i_alene2,2,'Justitsråd',ev);
    SET LOCAL ROLE authenticated;
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE EXCEPTION 'FORSLAG_TEST_NO_ERROR: anden nøgle';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    IF SQLERRM NOT LIKE 'FORSLAG_BINDING_TABT%' THEN RAISE EXCEPTION 'FORSLAG_TEST_ANDEN_NOEGLE: %',SQLERRM; END IF;
  END;
  SET CONSTRAINTS ALL DEFERRED;
END $laesning$;
ROLLBACK;
SELECT 'forslag_laesning OK' AS result;
