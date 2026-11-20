\set ON_ERROR_STOP on
-- OCR-rettelse af kildepåstand uden importanker (decisions 2026-11-20). red_ret_ocr_paastand retter en importeret
-- kildepåstand på samme id (B12's OCR-undtagelse) med redaktørens læsning af bogen; originalen står i
-- paastand_korrektion (grund 'ocr') og change_event. Kører i evidence-promotion-jobbene efter test-paastand-rettelse.sql.
-- Alt syntetisk; rulles tilbage, så filen kan køres flere gange mod samme base.
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql

-- Et afklaret faktum med én påstand, citeret af p_sources (NULL-element = citation uden kilde).
CREATE FUNCTION pg_temp.op_fakta(p_person bigint,p_faktatype text,p_kind text,p_value text,p_sources bigint[],
  p_min date DEFAULT NULL,p_max date DEFAULT NULL,p_certainty text DEFAULT NULL,p_uforanderlig boolean DEFAULT true)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_fact bigint; v_a bigint; i int;
BEGIN
  INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',p_person,p_faktatype) RETURNING id INTO v_fact;
  IF p_kind='text' THEN
    INSERT INTO assertion(target_type,target_id,vaerdi_tekst,uforanderlig)
      VALUES ('fact',v_fact,p_value,p_uforanderlig) RETURNING id INTO v_a;
  ELSE
    INSERT INTO assertion(target_type,target_id,date_raw,date_min,date_max,date_qualifier,calendar,date_certainty,
                          uforanderlig)
      VALUES ('fact',v_fact,p_value,p_min,p_max,CASE WHEN p_min IS NULL THEN NULL ELSE 'exact' END,'gregoriansk',
              p_certainty,p_uforanderlig) RETURNING id INTO v_a;
  END IF;
  INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_fact,v_a,'afklaret');
  FOR i IN 1..cardinality(p_sources) LOOP
    INSERT INTO citation(assertion_id,source_id,citat_tekst,side) VALUES (v_a,p_sources[i],'ocr','529');
  END LOOP;
  RETURN v_a;
END $$;

CREATE FUNCTION pg_temp.op_forventet(p_a bigint) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('fact_id',f.id,'faktatype',f.faktatype,'vaerdi_tekst',a.vaerdi_tekst,'date_raw',a.date_raw,
           'valgt_assertion_id',c.valgt_assertion_id,
           'citation_sources',(SELECT coalesce(jsonb_agg(DISTINCT ci.source_id ORDER BY ci.source_id)
                                                 FILTER (WHERE ci.source_id IS NOT NULL),'[]'::jsonb)
                                 FROM citation ci WHERE ci.assertion_id=a.id))
    FROM assertion a JOIN fact f ON f.id=a.target_id
    LEFT JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
   WHERE a.id=p_a
$$;

-- Rettelse som p_role med redaktør-uid p_actor; returnerer kvitteringen.
CREATE FUNCTION pg_temp.op_ret(p_actor uuid,p_a bigint,p_forv jsonb,p_ny jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  r:=public.red_ret_ocr_paastand(p_a,p_forv,p_ny);
  RESET ROLE;
  PERFORM set_config('app.change_set_id','',true);
  RETURN r;
END $$;

-- Forventet fejl; påstand og journal skal være uændrede bagefter.
CREATE FUNCTION pg_temp.op_fejl(p_token text,p_actor uuid,p_a bigint,p_forv jsonb,p_ny jsonb,
  p_role text DEFAULT 'authenticated') RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_foer jsonb; v_n bigint;
BEGIN
  SELECT to_jsonb(a) INTO v_foer FROM assertion a WHERE id=p_a;
  SELECT count(*) INTO v_n FROM paastand_korrektion;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub',coalesce(p_actor::text,''),true);
    PERFORM set_config('app.change_set_id','',true);
    EXECUTE format('SET LOCAL ROLE %I',p_role);
    PERFORM public.red_ret_ocr_paastand(p_a,p_forv,p_ny);
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    PERFORM set_config('app.change_set_id','',true);
    IF SQLERRM IS NULL OR SQLERRM NOT LIKE p_token||'%' THEN
      RAISE EXCEPTION 'OCRP_TEST_WRONG_ERROR: expected % got %',p_token,SQLERRM;
    END IF;
    IF (SELECT to_jsonb(a) FROM assertion a WHERE id=p_a) IS DISTINCT FROM v_foer
       OR (SELECT count(*) FROM paastand_korrektion)<>v_n THEN
      RAISE EXCEPTION 'OCRP_TEST_SIDEEFFEKT: %',p_token;
    END IF;
    RETURN;
  END;
  RESET ROLE;
  RAISE EXCEPTION 'OCRP_TEST_NO_ERROR: expected %',p_token;
END $$;

-- 1) Adgang: kun authenticated kan kalde; journalen tillader grunden 'ocr'.
DO $adgang$
BEGIN
  IF to_regprocedure('public.red_ret_ocr_paastand(bigint,jsonb,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'OCRP_TEST_MANGLER: red_ret_ocr_paastand';
  END IF;
  IF has_function_privilege('anon','public.red_ret_ocr_paastand(bigint,jsonb,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_ret_ocr_paastand(bigint,jsonb,jsonb)','EXECUTE')
     OR NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid='public.red_ret_ocr_paastand(bigint,jsonb,jsonb)'::regprocedure) THEN
    RAISE EXCEPTION 'OCRP_TEST_ACL';
  END IF;
END $adgang$;

-- 2) Rettelser og afvisninger. Person -2871 er ankerløs; -2872 har ét stabilt anker i kilde -2871.
DO $ocr$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-0000000c2871'; v_medlem uuid:='11000000-0000-0000-0000-0000000c2872';
  v_p bigint:=-2871; v_s bigint:=-2871; m jsonb; v_post jsonb; v_run uuid;
  a_foed bigint; a_navn bigint; a_ufort bigint; a_egen bigint; a_fri bigint; a_delt bigint; a_ff bigint;
  a_anker bigint; a_bund bigint; i_bund uuid; a_titel bigint; a_valgt_egen bigint; a_egen_ovenpaa bigint;
  r jsonb; a record; v_cs bigint; h record; v_ny jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO auth.users(id,email) VALUES (v_medlem,'medlem@ocrp.invalid');
  INSERT INTO profiles(id,rolle,navn,email) VALUES (v_medlem,'medlem','Medlem ocrp','medlem@ocrp.invalid');
  INSERT INTO person(id,levende,privat,status) VALUES (v_p,false,false,'ocrp'),(-2872,false,false,'ocrp');
  m:=pg_temp.f5b_source(v_s);
  PERFORM pg_temp.f5b_source(-2873);
  UPDATE source SET import_key='ocrp:kilde' WHERE id=v_s;
  INSERT INTO person_external_id(person_id,source_id,record_key) VALUES (-2872,v_s,'ocrp-1');

  a_foed:=pg_temp.op_fakta(v_p,'fødsel','date_raw','25 Marts 157',ARRAY[v_s]);
  a_navn:=pg_temp.op_fakta(v_p,'navn','text','Sophie von Sperlinq',ARRAY[v_s]);
  a_ufort:=pg_temp.op_fakta(v_p,'død','date_raw','3 Maj 16O2',ARRAY[v_s],NULL,NULL,'ambiguous');
  a_egen:=pg_temp.op_fakta(v_p,'titel','text','Hofdame',ARRAY[NULL::bigint],NULL,NULL,NULL,false);
  a_fri:=pg_temp.op_fakta(v_p,'titel','text','Kammerfrøken',ARRAY[NULL::bigint]);
  a_delt:=pg_temp.op_fakta(v_p,'titel','text','Stiftsdame',ARRAY[v_s,-2873]);
  a_ff:=pg_temp.op_fakta(v_p,'forældrefamilie','text','x',ARRAY[v_s]);
  a_anker:=pg_temp.op_fakta(-2872,'fødsel','date_raw','1 Jan 160',ARRAY[v_s]);
  a_titel:=pg_temp.op_fakta(-2872,'titel','text','Kammerjunkr',ARRAY[v_s]);

  -- (a) Dato rettes på samme id; faktum har stadig én påstand; journal og cache følger.
  r:=pg_temp.op_ret(v_actor,a_foed,pg_temp.op_forventet(a_foed),
    '{"date_raw":"25 Marts 1578","date_min":"1578-03-25","date_max":"1578-03-25","date_qualifier":"exact","date_certainty":null}');
  SELECT * INTO a FROM assertion WHERE id=a_foed;
  IF a.date_raw<>'25 Marts 1578' OR a.date_min<>'1578-03-25' OR a.date_max<>'1578-03-25'
     OR a.date_qualifier IS DISTINCT FROM 'exact' OR a.date_certainty IS NOT NULL THEN
    RAISE EXCEPTION 'OCRP_TEST_DATO: %',to_jsonb(a);
  END IF;
  IF (SELECT count(*) FROM assertion WHERE target_type='fact' AND target_id=a.target_id)<>1 THEN
    RAISE EXCEPTION 'OCRP_TEST_NY_PAASTAND';
  END IF;
  IF (r->>'grund')<>'ocr' OR (r->>'assertion_id')::bigint<>a_foed
     OR (SELECT foer->>'date_raw' FROM paastand_korrektion WHERE id=(r->>'korrektion_id')::bigint)<>'25 Marts 157'
     OR (SELECT grund FROM paastand_korrektion WHERE id=(r->>'korrektion_id')::bigint)<>'ocr'
     OR (SELECT interpretation_id FROM paastand_korrektion WHERE id=(r->>'korrektion_id')::bigint) IS NOT NULL THEN
    RAISE EXCEPTION 'OCRP_TEST_JOURNAL: %',r;
  END IF;
  IF (SELECT operation FROM change_set WHERE id=(r->>'change_set_id')::bigint)<>'red_ret_ocr_paastand'
     OR NOT EXISTS (SELECT 1 FROM change_event WHERE change_set_id=(r->>'change_set_id')::bigint AND tabel='assertion') THEN
    RAISE EXCEPTION 'OCRP_TEST_CHANGE_SET';
  END IF;
  IF (SELECT visning_foedt FROM person WHERE id=v_p) IS DISTINCT FROM '25 Marts 1578' THEN
    RAISE EXCEPTION 'OCRP_TEST_VISNING: %',(SELECT visning_foedt FROM person WHERE id=v_p);
  END IF;
  v_cs:=(r->>'change_set_id')::bigint;

  -- (b) Fortrydelse: alle datokolonner tilbage, journalen står, historikken viser fortrydelsen, cachen følger.
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_fortryd_change_set(v_cs,false);
  RESET ROLE;
  PERFORM set_config('app.change_set_id','',true);
  SELECT * INTO a FROM assertion WHERE id=a_foed;
  IF a.date_raw<>'25 Marts 157' OR a.date_min IS NOT NULL OR a.date_max IS NOT NULL OR a.date_qualifier IS NOT NULL
     OR (SELECT count(*) FROM paastand_korrektion WHERE assertion_id=a_foed)<>1
     OR (SELECT visning_foedt FROM person WHERE id=v_p) IS DISTINCT FROM '25 Marts 157' THEN
    RAISE EXCEPTION 'OCRP_TEST_FORTRYD: %',to_jsonb(a);
  END IF;
  SET LOCAL ROLE authenticated;
  SELECT * INTO h FROM public.red_paastand_historik(a_foed);
  RESET ROLE;
  IF h.fortrudt IS NOT TRUE OR h.grund<>'ocr' THEN RAISE EXCEPTION 'OCRP_TEST_HISTORIK'; END IF;

  -- (c) Tekst rettes.
  r:=pg_temp.op_ret(v_actor,a_navn,pg_temp.op_forventet(a_navn),'{"vaerdi_tekst":"Sophie von Sperling"}');
  IF (SELECT vaerdi_tekst FROM assertion WHERE id=a_navn)<>'Sophie von Sperling'
     OR (SELECT foer->>'vaerdi_tekst' FROM paastand_korrektion WHERE id=(r->>'korrektion_id')::bigint)<>'Sophie von Sperlinq' THEN
    RAISE EXCEPTION 'OCRP_TEST_TEKST: %',r;
  END IF;

  -- (d) Ufortolkelig dato kan gemmes uden fortolkning; en gammel certainty overlever ikke.
  r:=pg_temp.op_ret(v_actor,a_ufort,pg_temp.op_forventet(a_ufort),
    '{"date_raw":"3 Maj 16?2","date_min":null,"date_max":null,"date_qualifier":null,"date_certainty":null}');
  SELECT * INTO a FROM assertion WHERE id=a_ufort;
  IF a.date_raw<>'3 Maj 16?2' OR a.date_min IS NOT NULL OR a.date_certainty IS NOT NULL
     OR r->'foer'->>'date_certainty' IS DISTINCT FROM 'ambiguous' THEN
    RAISE EXCEPTION 'OCRP_TEST_UFORTOLKELIG: %',to_jsonb(a);
  END IF;

  -- (e) Afvisninger.
  v_ny:='{"vaerdi_tekst":"Overhofmesterinde"}';
  PERFORM pg_temp.op_fejl('PAASTAND_ROLLE_FORBUDT',v_medlem,a_navn,pg_temp.op_forventet(a_navn),v_ny);
  PERFORM pg_temp.op_fejl('PAASTAND_ROLLE_FORBUDT',NULL,a_navn,pg_temp.op_forventet(a_navn),v_ny);
  PERFORM pg_temp.op_fejl('PAASTAND_DRIFT',v_actor,a_foed,
    pg_temp.op_forventet(a_foed)||'{"date_raw":"25 Marts 1578"}',
    '{"date_raw":"25 Marts 1579","date_min":null,"date_max":null,"date_qualifier":null,"date_certainty":null}');
  PERFORM pg_temp.op_fejl('PAASTAND_DRIFT',v_actor,-987650001,pg_temp.op_forventet(a_navn),v_ny);
  PERFORM pg_temp.op_fejl('PAASTAND_IKKE_KILDEPAASTAND',v_actor,a_egen,pg_temp.op_forventet(a_egen),v_ny);
  PERFORM pg_temp.op_fejl('PAASTAND_IKKE_KILDEPAASTAND',v_actor,a_fri,pg_temp.op_forventet(a_fri),v_ny);
  PERFORM pg_temp.op_fejl('PAASTAND_KILDE_DELT',v_actor,a_delt,pg_temp.op_forventet(a_delt),v_ny);
  PERFORM pg_temp.op_fejl('PAASTAND_FAKTATYPE_UGYLDIG',v_actor,a_ff,pg_temp.op_forventet(a_ff),v_ny);
  PERFORM pg_temp.op_fejl('PAASTAND_BRUG_KVALITETSARK',v_actor,a_anker,pg_temp.op_forventet(a_anker),
    '{"date_raw":"1 Jan 1600","date_min":"1600-01-01","date_max":"1600-01-01","date_qualifier":"exact","date_certainty":null}');
  -- Kvalitetsarket kan kun rette den valgte, afklarede påstand, ankerets kilde citerer: har en redaktør lagt en egen
  -- oplysning ovenpå (konklusionen peger på den), rettes kildepåstanden her i stedet for at blive henvist til arket.
  a_valgt_egen:=pg_temp.op_fakta(-2872,'død','date_raw','5 Maj 165',ARRAY[v_s]);
  INSERT INTO assertion(target_type,target_id,date_raw,uforanderlig)
    SELECT 'fact',target_id,'5 Maj 1650',false FROM assertion WHERE id=a_valgt_egen RETURNING id INTO a_egen_ovenpaa;
  UPDATE conclusion SET valgt_assertion_id=a_egen_ovenpaa
   WHERE target_type='fact' AND target_id=(SELECT target_id FROM assertion WHERE id=a_valgt_egen);
  r:=pg_temp.op_ret(v_actor,a_valgt_egen,pg_temp.op_forventet(a_valgt_egen),
    '{"date_raw":"5 Maj 1650","date_min":"1650-01-01","date_max":"1650-12-31","date_qualifier":null,"date_certainty":null}');
  IF (SELECT date_raw FROM assertion WHERE id=a_valgt_egen)<>'5 Maj 1650' THEN RAISE EXCEPTION 'OCRP_TEST_ANKER_IKKE_VALGT'; END IF;
  -- Ankeret dækker kun navn/fødsel/død: en titel hos samme person rettes her.
  r:=pg_temp.op_ret(v_actor,a_titel,pg_temp.op_forventet(a_titel),'{"vaerdi_tekst":"Kammerjunker"}');
  IF (SELECT vaerdi_tekst FROM assertion WHERE id=a_titel)<>'Kammerjunker' THEN RAISE EXCEPTION 'OCRP_TEST_ANKER_TITEL'; END IF;
  -- Ugyldige værdier.
  PERFORM pg_temp.op_fejl('PAASTAND_VAERDI_UGYLDIG',v_actor,a_navn,pg_temp.op_forventet(a_navn),'{"vaerdi_tekst":"  "}');
  PERFORM pg_temp.op_fejl('PAASTAND_VAERDI_UGYLDIG',v_actor,a_navn,pg_temp.op_forventet(a_navn),'"Sophie"');
  PERFORM pg_temp.op_fejl('PAASTAND_VAERDI_UGYLDIG',v_actor,a_navn,pg_temp.op_forventet(a_navn),
    '{"vaerdi_tekst":"Sophie","ekstra":1}');
  PERFORM pg_temp.op_fejl('PAASTAND_VAERDI_UGYLDIG',v_actor,a_navn,pg_temp.op_forventet(a_navn),
    '{"date_raw":"1578","date_min":null,"date_max":null,"date_qualifier":null,"date_certainty":null}');
  PERFORM pg_temp.op_fejl('PAASTAND_VAERDI_UGYLDIG',v_actor,a_foed,pg_temp.op_forventet(a_foed),
    '{"vaerdi_tekst":"25 Marts 1578"}');
  PERFORM pg_temp.op_fejl('PAASTAND_VAERDI_UGYLDIG',v_actor,a_foed,pg_temp.op_forventet(a_foed),
    '{"date_raw":"25 Marts 1578","date_min":"1578-03-26","date_max":"1578-03-25","date_qualifier":null,"date_certainty":null}');
  PERFORM pg_temp.op_fejl('PAASTAND_VAERDI_UGYLDIG',v_actor,a_foed,pg_temp.op_forventet(a_foed),
    '{"date_raw":"25 Marts 1578","date_min":null,"date_max":null,"date_qualifier":"ca","date_certainty":null}');
  PERFORM pg_temp.op_fejl('PAASTAND_VAERDI_UGYLDIG',v_actor,a_foed,pg_temp.op_forventet(a_foed),
    '{"date_raw":"25 Marts 1578","date_min":null,"date_max":null,"date_qualifier":null,"date_certainty":"sikker"}');
  PERFORM pg_temp.op_fejl('PAASTAND_VAERDI_UGYLDIG',v_actor,a_foed,pg_temp.op_forventet(a_foed),
    '{"date_raw":"25 Marts 1578","date_min":"marts","date_max":null,"date_qualifier":null,"date_certainty":null}');
  PERFORM pg_temp.op_fejl('PAASTAND_VAERDI_UGYLDIG',v_actor,a_foed,pg_temp.op_forventet(a_foed),
    '{"date_raw":"25 Marts 1578","date_min":null,"date_max":null,"date_qualifier":null}');
  PERFORM pg_temp.op_fejl('PAASTAND_VAERDI_UAENDRET',v_actor,a_navn,pg_temp.op_forventet(a_navn),
    '{"vaerdi_tekst":"Sophie von Sperling"}');
  PERFORM pg_temp.op_fejl('PAASTAND_VAERDI_UAENDRET',v_actor,a_foed,pg_temp.op_forventet(a_foed),
    '{"date_raw":"25 Marts 157","date_min":null,"date_max":null,"date_qualifier":null,"date_certainty":null}');

  -- (f) En gyldig binding, som den nye værdi bryder, afviser rettelsen.
  v_post:=pg_temp.f5b_post(v_s,m,'P2871','Sophie Sperling. Hofdame.',ARRAY['Sophie Sperling.','Hofdame.'],v_p,v_actor);
  v_run:=(m->>'run')::uuid;
  PERFORM pg_temp.f2a_event_for_state((v_post->>'principal')::uuid);
  a_bund:=pg_temp.op_fakta(v_p,'titel','text','Hofdame',ARRAY[v_s]);
  i_bund:=gen_random_uuid();
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
    predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES (i_bund,gen_random_uuid(),1,v_s,(v_post->>'principal')::uuid,'property','person.title',to_jsonb('Hofdame'::text),
      '1.0','source_statement',1,'proposed','fixture',v_run);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (i_bund,(v_post->'clauses'->>0)::uuid,'supporting',1);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_decide_interpretation(i_bund,1,'accepted','{"basis":"ocr-paastand"}');
  RESET ROLE;
  PERFORM set_config('app.change_set_id','',true);
  SELECT ic.id INTO i_bund FROM private.interpretation_current ic
    JOIN private.interpretation q ON q.interpretation_key=ic.interpretation_key WHERE q.id=i_bund;
  DECLARE items jsonb; pv jsonb;
  BEGIN
    SET LOCAL ROLE authenticated;
    items:=jsonb_build_array(jsonb_build_object('interpretation_id',i_bund::text,'target_type','assertion','target_id',a_bund));
    pv:=public.red_preview_interpretation_promotions(items);
    PERFORM public.red_promote_interpretations_batch(items,pv->>'preview_hash');
    RESET ROLE;
    PERFORM set_config('app.change_set_id','',true);
  END;
  IF NOT EXISTS (SELECT 1 FROM private.interpretation_promotion WHERE target_type='assertion' AND target_id=a_bund) THEN
    RAISE EXCEPTION 'OCRP_TEST_FIXTURE: ingen binding';
  END IF;
  PERFORM pg_temp.op_fejl('PAASTAND_BINDING_BRYDES',v_actor,a_bund,pg_temp.op_forventet(a_bund),
    '{"vaerdi_tekst":"Hofmesterinde"}');

  IF (SELECT count(*) FROM paastand_korrektion WHERE grund='ocr')<>5 THEN
    RAISE EXCEPTION 'OCRP_TEST_ANTAL: %',(SELECT count(*) FROM paastand_korrektion WHERE grund='ocr');
  END IF;
END $ocr$;
ROLLBACK;
SELECT 'ocr_paastand OK' AS result;
