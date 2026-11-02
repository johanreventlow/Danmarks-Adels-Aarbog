\set ON_ERROR_STOP on
-- Trin 6c-2b (spec 2026-11-02 §4.4 pkt. 4 og §4.5): påstandsnøglet rettelse. red_ret_paastand retter en påstand på samme
-- id (B12) med forslagets værdi (bogen_har_ret) eller påstandens egen værdi med blanktegn samlet (linjeskift-v1);
-- originalen står i paastand_korrektion og i change_event. Kører i evidence-promotion-db-jobbet. Alt syntetisk; rulles
-- tilbage, så filen kan køres flere gange mod samme base.
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql

-- Et afklaret faktum med én påstand, citeret af p_sources. p_kind er 'text' (vaerdi_tekst) eller 'date_raw'.
CREATE FUNCTION pg_temp.pr_fakta(p_person bigint,p_faktatype text,p_kind text,p_value text,p_sources bigint[],
  p_min date DEFAULT NULL,p_max date DEFAULT NULL) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_fact bigint; v_a bigint; s bigint;
BEGIN
  INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',p_person,p_faktatype) RETURNING id INTO v_fact;
  IF p_kind='text' THEN
    INSERT INTO assertion(target_type,target_id,vaerdi_tekst,uforanderlig)
      VALUES ('fact',v_fact,p_value,true) RETURNING id INTO v_a;
  ELSE
    INSERT INTO assertion(target_type,target_id,date_raw,date_min,date_max,date_qualifier,calendar,uforanderlig)
      VALUES ('fact',v_fact,p_value,p_min,p_max,'exact','gregoriansk',true) RETURNING id INTO v_a;
  END IF;
  INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_fact,v_a,'afklaret');
  FOREACH s IN ARRAY p_sources LOOP
    INSERT INTO citation(assertion_id,source_id,citat_tekst,side) VALUES (v_a,s,'pr','3');
  END LOOP;
  RETURN v_a;
END $$;

-- Et forslag (version 1, proposed) fra postens hovedperson-persona.
CREATE FUNCTION pg_temp.pr_forslag(p_source bigint,p_post jsonb,p_run uuid,p_predicate text,p_value text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_int uuid:=gen_random_uuid();
BEGIN
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
    predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES (v_int,gen_random_uuid(),1,p_source,(p_post->>'principal')::uuid,'property',p_predicate,to_jsonb(p_value),
      '1.0','source_statement',1,'proposed','fixture',p_run);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_int,(p_post->'clauses'->>0)::uuid,'supporting',1);
  RETURN v_int;
END $$;

-- Afgør et forslag som redaktør; returnerer den gældende (nye) version.
CREATE FUNCTION pg_temp.pr_afgoer(p_actor uuid,p_int uuid,p_status text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid; v_version integer;
BEGIN
  SELECT version INTO v_version FROM private.interpretation WHERE id=p_int;
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_decide_interpretation(p_int,v_version,p_status,'{"basis":"paastand-rettelse"}');
  RESET ROLE;
  PERFORM set_config('app.change_set_id','',true);
  SELECT ic.id INTO v_id FROM private.interpretation_current ic
    JOIN private.interpretation q ON q.interpretation_key=ic.interpretation_key WHERE q.id=p_int;
  RETURN v_id;
END $$;

-- Binder et accepteret forslag til en påstand gennem preview + batch.
CREATE FUNCTION pg_temp.pr_bind(p_int uuid,p_a bigint) RETURNS uuid LANGUAGE plpgsql AS $$
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
  IF v_prom IS NULL THEN RAISE EXCEPTION 'PAASTAND_TEST_FIXTURE: ingen promotion'; END IF;
  RETURN v_prom;
END $$;

-- Det forventede mål, som kortet viser det.
CREATE FUNCTION pg_temp.pr_forventet(p_a bigint) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('fact_id',f.id,'faktatype',f.faktatype,'vaerdi_tekst',a.vaerdi_tekst,'date_raw',a.date_raw,
           'valgt_assertion_id',c.valgt_assertion_id,
           'citation_sources',(SELECT jsonb_agg(DISTINCT ci.source_id ORDER BY ci.source_id)
                                 FROM citation ci WHERE ci.assertion_id=a.id))
    FROM assertion a JOIN fact f ON f.id=a.target_id
    LEFT JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
   WHERE a.id=p_a
$$;

-- Rettelse som redaktør; returnerer kvitteringen.
CREATE FUNCTION pg_temp.pr_ret(p_a bigint,p_forv jsonb,p_grund text,p_int uuid,p_dato jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  r:=public.red_ret_paastand(p_a,p_forv,p_grund,p_int,p_dato);
  RESET ROLE;
  PERFORM set_config('app.change_set_id','',true);
  RETURN r;
END $$;

-- Forventet fejl fra red_ret_paastand, kaldt som p_role. Påstanden kontrolleres uændret bagefter af kalderen.
CREATE FUNCTION pg_temp.pr_fejl(p_token text,p_a bigint,p_forv jsonb,p_grund text,p_int uuid,p_dato jsonb DEFAULT NULL,
  p_role text DEFAULT 'authenticated') RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    EXECUTE format('SET LOCAL ROLE %I',p_role);
    PERFORM public.red_ret_paastand(p_a,p_forv,p_grund,p_int,p_dato);
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    IF SQLERRM IS NULL OR SQLERRM NOT LIKE p_token||'%' THEN
      RAISE EXCEPTION 'PAASTAND_TEST_WRONG_ERROR: expected % got %',p_token,SQLERRM;
    END IF;
    RETURN;
  END;
  RESET ROLE;
  RAISE EXCEPTION 'PAASTAND_TEST_NO_ERROR: expected %',p_token;
END $$;

-- 1) De delte regler: blanktegnssamling og navneforkortelse.
DO $regler$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    (E'12. marts\n1702', '12. marts 1702'),
    (E'  12.\t marts\r\n1702 ', '12. marts 1702'),
    (E'12.\fmarts\0131702', '12. marts 1702'),
    (E'12.\u00a0marts\u2009\u202f1702', '12. marts 1702'),
    (E'\u2028 12. marts 1702\u2029', '12. marts 1702'),
    ('12. marts 1702', '12. marts 1702'),
    ('', '')) v(i,o)
  LOOP
    IF private.saml_blanktegn_v1(r.i) IS DISTINCT FROM r.o THEN
      RAISE EXCEPTION 'PAASTAND_TEST_BLANKTEGN: % gav % (ventede %)',r.i,private.saml_blanktegn_v1(r.i),r.o;
    END IF;
  END LOOP;
  IF private.saml_blanktegn_v1(NULL) IS NOT NULL THEN RAISE EXCEPTION 'PAASTAND_TEST_BLANKTEGN: NULL'; END IF;
  FOR r IN SELECT * FROM (VALUES
    ('Ditlev Reventlow til X', 'Ditlev', true),
    ('Ditlev Reventlow til X', E'ditlev\u00a0 reventlow', true),
    ('Ditlev  Reventlow', 'ditlev reventlow', false),
    ('Ditlev', 'Ditlev Reventlow', false),
    ('Ditlev Reventlow', 'Christian', false),
    ('Ditlev Reventlow', 'Ditlew Reventlow', false)) v(g,n,o)
  LOOP
    IF private.navn_forkortes(r.g,r.n) IS DISTINCT FROM r.o THEN
      RAISE EXCEPTION 'PAASTAND_TEST_NAVNEREGEL: % -> % gav %',r.g,r.n,private.navn_forkortes(r.g,r.n);
    END IF;
  END LOOP;
  IF (SELECT provolatile FROM pg_proc WHERE oid='private.saml_blanktegn_v1(text)'::regprocedure)<>'i'
     OR (SELECT provolatile FROM pg_proc WHERE oid='private.navn_forkortes(text,text)'::regprocedure)<>'i' THEN
    RAISE EXCEPTION 'PAASTAND_TEST_IMMUTABLE';
  END IF;
END $regler$;

-- 2) Adgang: tabellen har RLS og ingen klientadgang; hjælperne er private; RPC'erne kun for authenticated.
DO $adgang$
DECLARE v_role text; v_priv text;
BEGIN
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.paastand_korrektion'::regclass) THEN
    RAISE EXCEPTION 'PAASTAND_TEST_RLS';
  END IF;
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    FOREACH v_priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE'] LOOP
      IF has_table_privilege(v_role,'public.paastand_korrektion',v_priv) THEN
        RAISE EXCEPTION 'PAASTAND_TEST_GRANT: % %',v_role,v_priv;
      END IF;
    END LOOP;
    IF has_function_privilege(v_role,'private.saml_blanktegn_v1(text)','EXECUTE')
       OR has_function_privilege(v_role,'private.navn_forkortes(text,text)','EXECUTE') THEN
      RAISE EXCEPTION 'PAASTAND_TEST_HJAELPER_ACL: %',v_role;
    END IF;
  END LOOP;
  IF has_function_privilege('anon','public.red_ret_paastand(bigint,jsonb,text,uuid,jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.red_paastand_historik(bigint)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_ret_paastand(bigint,jsonb,text,uuid,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_paastand_historik(bigint)','EXECUTE') THEN
    RAISE EXCEPTION 'PAASTAND_TEST_RPC_ACL';
  END IF;
END $adgang$;

-- 3) Rettelserne. Person -2861 med post og persona i kilde -2861 (identitet accepteret); -2862 er en anden person med
-- en persona i samme kilde; kilde -2863 citerer også én påstand; kilde -2864 har en persona for samme person.
DO $rettelse$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-0000006c2b03'; v_medlem uuid:='11000000-0000-0000-0000-0000006c2b04';
  m jsonb; v_post jsonb; v_run uuid; v_p bigint:=-2861; v_s bigint:=-2861;
  s3 jsonb; post3 jsonb; post4 jsonb;
  a_titel bigint; i_titel uuid; a_foed bigint; i_foed uuid; i_foed2 uuid; a_doed bigint; i_doed uuid;
  a_delt bigint; i_delt uuid; a_anden bigint; i_anden uuid; i_afvist uuid; i_person uuid; i_praed uuid;
  a_navn bigint; i_navn uuid; a_bund bigint; i_bund uuid; i_bund2 uuid; v_prom uuid; i_bryd uuid; a_koen bigint;
  a_doed2 bigint; i_doed2 uuid; a_bund_y bigint;
  r jsonb; forv jsonb; v_cs bigint; n int; a record; k record; h record; v_dato jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (v_p,false,false,'pr'),(-2862,false,false,'pr');
  m:=pg_temp.f5b_source(v_s);
  v_post:=pg_temp.f5b_post(v_s,m,'P2861','Anna Alfa. Kammerherre.',ARRAY['Anna Alfa.','Kammerherre.'],v_p,v_actor);
  v_run:=(m->>'run')::uuid;
  INSERT INTO auth.users(id,email) VALUES (v_medlem,'medlem@6c2b.invalid');
  INSERT INTO profiles(id,rolle,navn,email) VALUES (v_medlem,'medlem','Medlem 6c2b','medlem@6c2b.invalid');
  PERFORM pg_temp.f5b_source(-2863);
  s3:=pg_temp.f5b_source(-2864);
  post3:=pg_temp.f5b_post(-2864,s3,'P2864','Anna Alfa. Kammerherre.',ARRAY['Anna Alfa.','Kammerherre.'],v_p,v_actor);
  post4:=pg_temp.f5b_post(v_s,m,'Q2861','Bo Beta. Kammerherre.',ARRAY['Bo Beta.','Kammerherre.'],-2862,v_actor);
  PERFORM pg_temp.f2a_event_for_state((v_post->>'principal')::uuid);
  PERFORM pg_temp.f2a_event_for_state((post3->>'principal')::uuid);
  PERFORM pg_temp.f2a_event_for_state((post4->>'principal')::uuid);

  a_titel:=pg_temp.pr_fakta(v_p,'titel','text','Kammerherre',ARRAY[v_s]);
  i_titel:=pg_temp.pr_forslag(v_s,v_post,v_run,'person.title','Overhofmarskal');
  a_foed:=pg_temp.pr_fakta(v_p,'fødsel','date_raw','12. marts 1703',ARRAY[v_s],'1703-03-12','1703-03-12');
  i_foed:=pg_temp.pr_forslag(v_s,v_post,v_run,'person.birth','12. marts 1702');
  a_doed:=pg_temp.pr_fakta(v_p,'død','date_raw',E'12. marts\n1750',ARRAY[v_s],'1750-03-12','1750-03-12');
  i_doed:=pg_temp.pr_forslag(v_s,v_post,v_run,'person.death','12. marts 1750');
  a_delt:=pg_temp.pr_fakta(v_p,'titel','text','Etatsråd',ARRAY[v_s,-2863]);
  i_delt:=pg_temp.pr_forslag(v_s,v_post,v_run,'person.title','Konferensråd');
  a_anden:=pg_temp.pr_fakta(v_p,'titel','text','Justitsråd',ARRAY[v_s]);
  i_anden:=pg_temp.pr_forslag(-2864,post3,(s3->>'run')::uuid,'person.title','Konferensråd');
  i_afvist:=pg_temp.pr_forslag(v_s,v_post,v_run,'person.title','Gehejmeråd');
  i_person:=pg_temp.pr_forslag(v_s,post4,v_run,'person.title','Gehejmeråd');
  i_praed:=pg_temp.pr_forslag(v_s,v_post,v_run,'person.birth','1702');
  a_navn:=pg_temp.pr_fakta(v_p,'navn','text','Ditlev Reventlow til X',ARRAY[v_s]);
  i_navn:=pg_temp.pr_forslag(v_s,v_post,v_run,'person.name','Ditlev');
  a_bund:=pg_temp.pr_fakta(v_p,'titel','text','Kammerjunker',ARRAY[v_s]);
  i_bund:=pg_temp.pr_forslag(v_s,v_post,v_run,'person.title','Kammerjunker');
  i_bryd:=pg_temp.pr_forslag(v_s,v_post,v_run,'person.title','Kammerherre');
  a_koen:=pg_temp.pr_fakta(v_p,'koen','text','mand',ARRAY[v_s]);
  a_doed2:=pg_temp.pr_fakta(v_p,'død','date_raw',E'12. marts\n1750',ARRAY[v_s],'1750-03-12','1750-03-12');
  i_doed2:=pg_temp.pr_forslag(v_s,v_post,v_run,'person.death','12. marts 1751');
  a_bund_y:=pg_temp.pr_fakta(v_p,'titel','text','Kancelliråd',ARRAY[v_s]);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  i_foed2:=pg_temp.pr_afgoer(v_actor,i_foed,'accepted');
  i_afvist:=pg_temp.pr_afgoer(v_actor,i_afvist,'rejected');
  i_bund2:=pg_temp.pr_afgoer(v_actor,i_bund,'accepted');
  v_prom:=pg_temp.pr_bind(i_bund2,a_bund);
  IF NOT private.assertion_binding_current(v_prom) THEN RAISE EXCEPTION 'PAASTAND_TEST_FIXTURE: binding ugyldig'; END IF;

  -- (a) Rolle: ingen aktør, et medlem og anon.
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM pg_temp.pr_fejl('PAASTAND_ROLLE_FORBUDT',a_titel,pg_temp.pr_forventet(a_titel),'bogen_har_ret',i_titel);
  PERFORM set_config('request.jwt.claim.sub',v_medlem::text,true);
  PERFORM pg_temp.pr_fejl('PAASTAND_ROLLE_FORBUDT',a_titel,pg_temp.pr_forventet(a_titel),'bogen_har_ret',i_titel);
  PERFORM pg_temp.pr_fejl('permission denied',a_titel,pg_temp.pr_forventet(a_titel),'bogen_har_ret',i_titel,NULL,'anon');
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);

  -- (b) Grund.
  PERFORM pg_temp.pr_fejl('PAASTAND_GRUND_UGYLDIG',a_titel,pg_temp.pr_forventet(a_titel),'andet',i_titel);
  PERFORM pg_temp.pr_fejl('PAASTAND_GRUND_UGYLDIG',a_titel,pg_temp.pr_forventet(a_titel),NULL,i_titel);

  -- (c) Drift: værdi, citationsmængde, valgt påstand, manglende nøgle, ukendt påstand.
  forv:=pg_temp.pr_forventet(a_titel);
  PERFORM pg_temp.pr_fejl('PAASTAND_DRIFT',a_titel,forv||'{"vaerdi_tekst":"Kammerjunker"}','bogen_har_ret',i_titel);
  PERFORM pg_temp.pr_fejl('PAASTAND_DRIFT',a_titel,forv||jsonb_build_object('citation_sources',jsonb_build_array(v_s,-2863)),
    'bogen_har_ret',i_titel);
  PERFORM pg_temp.pr_fejl('PAASTAND_DRIFT',a_titel,forv||jsonb_build_object('valgt_assertion_id',a_doed),'bogen_har_ret',i_titel);
  PERFORM pg_temp.pr_fejl('PAASTAND_DRIFT',a_titel,forv||jsonb_build_object('fact_id',(forv->>'fact_id')::bigint+1),
    'bogen_har_ret',i_titel);
  PERFORM pg_temp.pr_fejl('PAASTAND_DRIFT',a_titel,forv||'{"faktatype":"navn"}','bogen_har_ret',i_titel);
  PERFORM pg_temp.pr_fejl('PAASTAND_DRIFT',a_titel,forv-'date_raw','bogen_har_ret',i_titel);
  PERFORM pg_temp.pr_fejl('PAASTAND_DRIFT',a_titel,forv||'{"fact_id":"x"}','bogen_har_ret',i_titel);
  PERFORM pg_temp.pr_fejl('PAASTAND_DRIFT',a_titel,NULL,'bogen_har_ret',i_titel);
  PERFORM pg_temp.pr_fejl('PAASTAND_DRIFT',-999999,forv,'bogen_har_ret',i_titel);

  -- (d) Faktatype og dato-parameter.
  PERFORM pg_temp.pr_fejl('PAASTAND_FAKTATYPE_UGYLDIG',a_koen,pg_temp.pr_forventet(a_koen),'bogen_har_ret',i_titel);
  PERFORM pg_temp.pr_fejl('PAASTAND_FAKTATYPE_UGYLDIG',a_titel,forv,'linjeskift-v1',i_titel);
  PERFORM pg_temp.pr_fejl('PAASTAND_FAKTATYPE_UGYLDIG',a_titel,forv,'bogen_har_ret',i_titel,
    '{"date_min":null,"date_max":null,"date_qualifier":null}');
  forv:=pg_temp.pr_forventet(a_foed);
  PERFORM pg_temp.pr_fejl('PAASTAND_FAKTATYPE_UGYLDIG',a_foed,forv,'bogen_har_ret',i_foed2);
  PERFORM pg_temp.pr_fejl('PAASTAND_FAKTATYPE_UGYLDIG',a_foed,forv,'bogen_har_ret',i_foed2,'{"date_min":"1702-03-12"}');
  PERFORM pg_temp.pr_fejl('PAASTAND_FAKTATYPE_UGYLDIG',a_foed,forv,'bogen_har_ret',i_foed2,
    '{"date_min":"1702-13-40","date_max":"1702-03-12","date_qualifier":null}');
  PERFORM pg_temp.pr_fejl('PAASTAND_FAKTATYPE_UGYLDIG',a_foed,forv,'bogen_har_ret',i_foed2,
    '{"date_min":"1702-03-13","date_max":"1702-03-12","date_qualifier":null}');
  PERFORM pg_temp.pr_fejl('PAASTAND_FAKTATYPE_UGYLDIG',a_foed,forv,'bogen_har_ret',i_foed2,'[]');
  -- En skalar p_dato afvises af typetjekket, før nøglemængden læses.
  PERFORM pg_temp.pr_fejl('PAASTAND_FAKTATYPE_UGYLDIG',a_foed,forv,'bogen_har_ret',i_foed2,'5');
  PERFORM pg_temp.pr_fejl('PAASTAND_FAKTATYPE_UGYLDIG',a_foed,forv,'bogen_har_ret',i_foed2,'"x"');
  -- Kvalifikatoren skal være en, derive_date_info kan give (eller null); ingen ekstra nøgler.
  PERFORM pg_temp.pr_fejl('PAASTAND_FAKTATYPE_UGYLDIG',a_foed,forv,'bogen_har_ret',i_foed2,
    '{"date_min":"1702-03-12","date_max":"1702-03-12","date_qualifier":"bogus"}');
  PERFORM pg_temp.pr_fejl('PAASTAND_FAKTATYPE_UGYLDIG',a_foed,forv,'bogen_har_ret',i_foed2,
    '{"date_min":"1702-03-12","date_max":"1702-03-12","date_qualifier":"exact"}');
  PERFORM pg_temp.pr_fejl('PAASTAND_FAKTATYPE_UGYLDIG',a_foed,forv,'bogen_har_ret',i_foed2,
    '{"date_min":"1702-03-12","date_max":"1702-03-12","date_qualifier":null,"calendar":"juliansk"}');
  PERFORM pg_temp.pr_fejl('PAASTAND_FAKTATYPE_UGYLDIG',a_doed,pg_temp.pr_forventet(a_doed),'linjeskift-v1',i_doed,
    '{"date_min":null,"date_max":null,"date_qualifier":null}');

  -- (e) Kilde: påstanden citeret af to kilder; forslag fra en anden kilde end citationen.
  PERFORM pg_temp.pr_fejl('PAASTAND_KILDE_DELT',a_delt,pg_temp.pr_forventet(a_delt),'bogen_har_ret',i_delt);
  PERFORM pg_temp.pr_fejl('PAASTAND_KILDE_DELT',a_anden,pg_temp.pr_forventet(a_anden),'bogen_har_ret',i_anden);

  -- (f) Forslaget passer ikke: afvist, anden person, andet prædikat, overhalet version, ukendt id.
  forv:=pg_temp.pr_forventet(a_anden);
  PERFORM pg_temp.pr_fejl('PAASTAND_FORSLAG_UOVERENS',a_anden,forv,'bogen_har_ret',i_afvist);
  PERFORM pg_temp.pr_fejl('PAASTAND_FORSLAG_UOVERENS',a_anden,forv,'bogen_har_ret',i_person);
  PERFORM pg_temp.pr_fejl('PAASTAND_FORSLAG_UOVERENS',a_anden,forv,'bogen_har_ret',i_praed);
  PERFORM pg_temp.pr_fejl('PAASTAND_FORSLAG_UOVERENS',a_anden,forv,'bogen_har_ret',gen_random_uuid());
  PERFORM pg_temp.pr_fejl('PAASTAND_FORSLAG_UOVERENS',a_anden,forv,'bogen_har_ret',NULL);
  PERFORM pg_temp.pr_fejl('PAASTAND_FORSLAG_UOVERENS',a_foed,pg_temp.pr_forventet(a_foed),'bogen_har_ret',i_foed,
    '{"date_min":"1702-03-12","date_max":"1702-03-12","date_qualifier":null}');

  -- (g) Navn må ikke forkortes.
  PERFORM pg_temp.pr_fejl('PAASTAND_NAVN_FORKORTES',a_navn,pg_temp.pr_forventet(a_navn),'bogen_har_ret',i_navn);

  -- (h) En gyldig binding fra et andet forslag ville blive ugyldig.
  PERFORM pg_temp.pr_fejl('PAASTAND_BINDING_BRYDES',a_bund,pg_temp.pr_forventet(a_bund),'bogen_har_ret',i_bryd);
  IF NOT private.assertion_binding_current(v_prom) THEN RAISE EXCEPTION 'PAASTAND_TEST_BINDING_AENDRET'; END IF;
  -- (h2) Engangsreglens bindingsdel: i_bund2 har en gældende binding på a_bund, så den kan ikke rette en anden påstand.
  PERFORM pg_temp.pr_fejl('PAASTAND_FORSLAG_UOVERENS',a_bund_y,pg_temp.pr_forventet(a_bund_y),'bogen_har_ret',i_bund2);

  -- Ingen af de afviste kald har skrevet noget.
  IF EXISTS (SELECT 1 FROM paastand_korrektion)
     OR EXISTS (SELECT 1 FROM change_set WHERE operation='red_ret_paastand') THEN
    RAISE EXCEPTION 'PAASTAND_TEST_AFVIST_SKREV';
  END IF;
  IF (SELECT vaerdi_tekst FROM assertion WHERE id=a_titel)<>'Kammerherre'
     OR (SELECT vaerdi_tekst FROM assertion WHERE id=a_navn)<>'Ditlev Reventlow til X'
     OR (SELECT vaerdi_tekst FROM assertion WHERE id=a_bund)<>'Kammerjunker'
     OR (SELECT vaerdi_tekst FROM assertion WHERE id=a_bund_y)<>'Kancelliråd'
     OR (SELECT date_raw FROM assertion WHERE id=a_foed)<>'12. marts 1703' THEN
    RAISE EXCEPTION 'PAASTAND_TEST_AFVIST_AENDREDE';
  END IF;

  -- (i) bogen_har_ret på titel: samme id, journal, change_event, visningscache, historik.
  IF (SELECT visning_titel FROM person WHERE id=v_p) IS NULL THEN RAISE EXCEPTION 'PAASTAND_TEST_FIXTURE: visning_titel'; END IF;
  forv:=pg_temp.pr_forventet(a_titel);
  r:=pg_temp.pr_ret(a_titel,forv,'bogen_har_ret',i_titel);
  IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(r) key)
       <>ARRAY['assertion_id','change_set_id','efter','foer','grund','korrektion_id']
     OR (r->>'assertion_id')::bigint<>a_titel OR r->>'grund'<>'bogen_har_ret'
     OR r->'foer'->>'vaerdi_tekst'<>'Kammerherre' OR r->'efter'->>'vaerdi_tekst'<>'Overhofmarskal' THEN
    RAISE EXCEPTION 'PAASTAND_TEST_KVITTERING: %',r;
  END IF;
  v_cs:=(r->>'change_set_id')::bigint;
  SELECT * INTO a FROM assertion WHERE id=a_titel;
  IF a.vaerdi_tekst<>'Overhofmarskal' OR a.uforanderlig IS NOT TRUE
     OR (SELECT count(*) FROM assertion x WHERE x.target_type='fact' AND x.target_id=(forv->>'fact_id')::bigint)<>1
     OR (SELECT valgt_assertion_id FROM conclusion WHERE target_type='fact' AND target_id=(forv->>'fact_id')::bigint)<>a_titel THEN
    RAISE EXCEPTION 'PAASTAND_TEST_TITEL: %',to_jsonb(a);
  END IF;
  SELECT * INTO k FROM paastand_korrektion WHERE assertion_id=a_titel;
  GET DIAGNOSTICS n=ROW_COUNT;
  IF n<>1 OR k.id<>(r->>'korrektion_id')::bigint OR k.interpretation_id<>i_titel OR k.grund<>'bogen_har_ret'
     OR k.foer<>r->'foer' OR k.efter<>r->'efter' OR k.change_set_id<>v_cs OR k.actor_id<>v_actor
     OR k.actor_navn<>'5b fixture' OR (SELECT count(*) FROM paastand_korrektion)<>1 THEN
    RAISE EXCEPTION 'PAASTAND_TEST_JOURNAL: %',to_jsonb(k);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM change_set cs WHERE cs.id=v_cs AND cs.operation='red_ret_paastand'
                    AND cs.subjekt_type='person' AND cs.subjekt_id=v_p AND cs.actor_id=v_actor)
     OR (SELECT count(*) FROM change_event ce WHERE ce.change_set_id=v_cs AND ce.tabel='assertion'
           AND ce.row_pk->>'id'=a_titel::text AND ce.op='UPDATE'
           AND ce.foer->>'vaerdi_tekst'='Kammerherre' AND ce.efter->>'vaerdi_tekst'='Overhofmarskal')<>1 THEN
    RAISE EXCEPTION 'PAASTAND_TEST_CHANGE_EVENT';
  END IF;
  IF (SELECT visning_titel FROM person WHERE id=v_p)<>'Overhofmarskal' THEN
    RAISE EXCEPTION 'PAASTAND_TEST_VISNING: %',(SELECT visning_titel FROM person WHERE id=v_p);
  END IF;
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.red_paastand_historik(a_titel);
  SELECT * INTO h FROM public.red_paastand_historik(a_titel);
  RESET ROLE;
  IF n<>1 OR h.korrektion_id<>k.id OR h.change_set_id<>v_cs OR h.grund<>'bogen_har_ret' OR h.interpretation_id<>i_titel
     OR h.foer<>k.foer OR h.efter<>k.efter OR h.actor_navn<>'5b fixture' OR h.fortrudt IS NOT FALSE
     OR h.changed_at IS NULL THEN
    RAISE EXCEPTION 'PAASTAND_TEST_HISTORIK: %',to_jsonb(h);
  END IF;
  PERFORM set_config('request.jwt.claim.sub',v_medlem::text,true);
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.red_paastand_historik(a_titel);
    RAISE EXCEPTION 'PAASTAND_TEST_NO_ERROR: historik som medlem';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    IF SQLERRM NOT LIKE 'PAASTAND_ROLLE_FORBUDT%' THEN RAISE EXCEPTION 'PAASTAND_TEST_HISTORIK_ROLLE: %',SQLERRM; END IF;
  END;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  -- Samme rettelse igen: værdien er allerede forslagets.
  PERFORM pg_temp.pr_fejl('PAASTAND_VAERDI_UAENDRET',a_titel,pg_temp.pr_forventet(a_titel),'bogen_har_ret',i_titel);
  -- Et forslag retter kun én påstand: i_titel kan ikke også bruges på a_anden.
  PERFORM pg_temp.pr_fejl('PAASTAND_FORSLAG_UOVERENS',a_anden,pg_temp.pr_forventet(a_anden),'bogen_har_ret',i_titel);
  IF (SELECT vaerdi_tekst FROM assertion WHERE id=a_anden)<>'Justitsråd'
     OR EXISTS (SELECT 1 FROM paastand_korrektion WHERE assertion_id=a_anden) THEN
    RAISE EXCEPTION 'PAASTAND_TEST_EN_PAASTAND_SKREV';
  END IF;

  -- (j) bogen_har_ret på fødsel med accepteret forslag: date_raw fra forslaget, grænser og kvalifikator fra p_dato.
  v_dato:='{"date_min":"1702-03-01","date_max":"1702-03-31","date_qualifier":"about"}';
  r:=pg_temp.pr_ret(a_foed,pg_temp.pr_forventet(a_foed),'bogen_har_ret',i_foed2,v_dato);
  SELECT * INTO a FROM assertion WHERE id=a_foed;
  IF a.date_raw<>'12. marts 1702' OR a.date_min<>'1702-03-01' OR a.date_max<>'1702-03-31' OR a.date_qualifier<>'about'
     OR a.calendar<>'gregoriansk' OR a.vaerdi_tekst IS NOT NULL
     OR r->'foer'->>'date_raw'<>'12. marts 1703' OR r->'foer'->>'date_min'<>'1703-03-12'
     OR r->'efter'->>'date_raw'<>'12. marts 1702' OR r->'efter'->>'date_min'<>'1702-03-01'
     OR r->'efter'->>'date_qualifier'<>'about' OR (r->>'change_set_id')::bigint=v_cs THEN
    RAISE EXCEPTION 'PAASTAND_TEST_FOEDSEL: % %',to_jsonb(a),r;
  END IF;
  IF (SELECT visning_foedt FROM person WHERE id=v_p)<>'12. marts 1702' THEN RAISE EXCEPTION 'PAASTAND_TEST_VISNING_FOEDT'; END IF;
  -- Rettelsen gør forslaget bindbart.
  v_prom:=pg_temp.pr_bind(i_foed2,a_foed);
  IF NOT private.assertion_binding_current(v_prom) THEN RAISE EXCEPTION 'PAASTAND_TEST_FOEDSEL_BINDING'; END IF;

  -- (k) linjeskift-v1 på død: kun blanktegn i date_raw; grænser og kvalifikator uændrede.
  r:=pg_temp.pr_ret(a_doed,pg_temp.pr_forventet(a_doed),'linjeskift-v1',i_doed);
  SELECT * INTO a FROM assertion WHERE id=a_doed;
  IF a.date_raw<>'12. marts 1750' OR a.date_min<>'1750-03-12' OR a.date_max<>'1750-03-12' OR a.date_qualifier<>'exact'
     OR r->'foer'->>'date_raw'<>E'12. marts\n1750' OR r->'efter'->>'date_raw'<>'12. marts 1750'
     OR r->'foer'->'date_min'<>r->'efter'->'date_min' OR r->'foer'->'date_max'<>r->'efter'->'date_max'
     OR (SELECT grund FROM paastand_korrektion WHERE id=(r->>'korrektion_id')::bigint)<>'linjeskift-v1'
     OR (SELECT interpretation_id FROM paastand_korrektion WHERE id=(r->>'korrektion_id')::bigint)<>i_doed THEN
    RAISE EXCEPTION 'PAASTAND_TEST_LINJESKIFT: % %',to_jsonb(a),r;
  END IF;
  PERFORM pg_temp.pr_fejl('PAASTAND_VAERDI_UAENDRET',a_doed,pg_temp.pr_forventet(a_doed),'linjeskift-v1',i_doed);
  -- linjeskift-v1 kræver, at den samlede værdi er forslagets: '12. marts\n1750' mod '12. marts 1751' afvises.
  PERFORM pg_temp.pr_fejl('PAASTAND_FORSLAG_UOVERENS',a_doed2,pg_temp.pr_forventet(a_doed2),'linjeskift-v1',i_doed2);
  IF (SELECT date_raw FROM assertion WHERE id=a_doed2)<>E'12. marts\n1750'
     OR EXISTS (SELECT 1 FROM paastand_korrektion WHERE assertion_id=a_doed2) THEN
    RAISE EXCEPTION 'PAASTAND_TEST_LINJESKIFT_SKREV';
  END IF;

  -- (l) Fortrydelse af titelrettelsen: påstanden og cachen tilbage; journalen bevares, historikken viser fortrydelsen.
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_fortryd_change_set(v_cs,false);
  RESET ROLE;
  PERFORM set_config('app.change_set_id','',true);
  IF (SELECT vaerdi_tekst FROM assertion WHERE id=a_titel)<>'Kammerherre'
     OR (SELECT visning_titel FROM person WHERE id=v_p)='Overhofmarskal'
     OR (SELECT count(*) FROM paastand_korrektion WHERE assertion_id=a_titel)<>1 THEN
    RAISE EXCEPTION 'PAASTAND_TEST_FORTRYD';
  END IF;
  SET LOCAL ROLE authenticated;
  SELECT * INTO h FROM public.red_paastand_historik(a_titel);
  RESET ROLE;
  IF h.fortrudt IS NOT TRUE THEN RAISE EXCEPTION 'PAASTAND_TEST_FORTRYD_HISTORIK'; END IF;
  -- Efter fortrydelsen er i_titel fri igen og kan bruges på a_anden.
  r:=pg_temp.pr_ret(a_anden,pg_temp.pr_forventet(a_anden),'bogen_har_ret',i_titel);
  IF (SELECT vaerdi_tekst FROM assertion WHERE id=a_anden)<>'Overhofmarskal' THEN
    RAISE EXCEPTION 'PAASTAND_TEST_GENBRUG_EFTER_FORTRYD: %',r;
  END IF;
  -- ... og nu har den rettet a_anden, så a_titel afviser den.
  PERFORM pg_temp.pr_fejl('PAASTAND_FORSLAG_UOVERENS',a_titel,pg_temp.pr_forventet(a_titel),'bogen_har_ret',i_titel);
  IF (SELECT count(*) FROM paastand_korrektion)<>4 THEN RAISE EXCEPTION 'PAASTAND_TEST_ANTAL'; END IF;
END $rettelse$;
ROLLBACK;
SELECT 'paastand_rettelse OK' AS result;
