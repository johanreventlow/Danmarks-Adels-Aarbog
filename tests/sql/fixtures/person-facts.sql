-- 5c-2/B11: ét afklaret dødsfaktum med citation og en gældende trin 4-binding til personens egen publicerede
-- post. Bygger på fixtures/relation-5b.sql og relation-2a.sql (indlæses først). Kald som ejer, før SET LOCAL ROLE.
-- Personen p_base er afdød og offentlig; p_base-1 er en anden offentlig person til flytte-tilfældene.
-- Forudsætningerne for red_ret_ocr_felt (schema.sql:1990-2040) er opfyldt: kilden har import_key, personen har
-- præcis én person_external_id-række med record_key, og den valgte assertion har præcis én citation i kilden.
CREATE OR REPLACE FUNCTION pg_temp.fpf_bound(p_base bigint,p_actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE s jsonb; post jsonb; v_text text:='Anna Alfa. Død 1850.'; v_fact bigint; v_assert bigint;
  v_int uuid:=gen_random_uuid(); v_key uuid:=gen_random_uuid(); pv jsonb; items jsonb; v_prom uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(p_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (p_base,false,false,'fpf'),(p_base-1,false,false,'fpf');
  s:=pg_temp.f5b_source(p_base);
  UPDATE public.source SET import_key='verify:fpf'||abs(p_base),udgave='DAA fpf' WHERE id=p_base;
  post:=pg_temp.f5b_post(p_base,s,'P'||abs(p_base),v_text,ARRAY['Død 1850.'],p_base,p_actor);
  PERFORM pg_temp.f2a_event_for_state((post->>'principal')::uuid);
  PERFORM pg_temp.f2a_publish(p_base,s,post,p_base,p_actor,v_text);
  INSERT INTO person_external_id(person_id,source_id,linje,nr,record_key) VALUES (p_base,p_base,'A',1,'P'||abs(p_base));
  INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',p_base,'død') RETURNING id INTO v_fact;
  INSERT INTO assertion(target_type,target_id,date_raw,calendar,uforanderlig)
    VALUES ('fact',v_fact,'1850','gregoriansk',true) RETURNING id INTO v_assert;
  INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_fact,v_assert,'afklaret');
  INSERT INTO citation(assertion_id,source_id,citat_tekst) VALUES (v_assert,p_base,'Død 1850.');
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
    predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES (v_int,v_key,1,p_base,(post->>'principal')::uuid,'property','person.death',to_jsonb('1850'::text),'1.0',
      'source_statement',1,'proposed','fixture',(s->>'run')::uuid);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_int,(post->'clauses'->>0)::uuid,'supporting',1);
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_decide_interpretation(v_int,1,'accepted','{"basis":"fpf"}');
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  -- Afgørelsen skriver en ny version; promotionen skal pege på den gældende.
  SELECT ic.id INTO v_int FROM private.interpretation_current ic WHERE ic.interpretation_key=v_key;
  SET LOCAL ROLE authenticated;
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_int::text,'target_type','assertion','target_id',v_assert));
  pv:=public.red_preview_interpretation_promotions(items);
  PERFORM public.red_promote_interpretations_batch(items,pv->>'preview_hash');
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  SELECT id INTO v_prom FROM private.interpretation_promotion
   WHERE interpretation_id=v_int AND target_type='assertion' AND target_id=v_assert;
  IF v_prom IS NULL THEN RAISE EXCEPTION 'FPF_FIXTURE: ingen promotion'; END IF;
  RETURN jsonb_build_object('person',p_base,'other',p_base-1,'fact',v_fact,'assertion',v_assert,
    'interpretation',v_int,'interpretation_key',v_key,'promotion',v_prom,'source',p_base,'post',post,'src',s,
    'items',items,'import_key','verify:fpf'||abs(p_base),'record_key','P'||abs(p_base));
END $$;

-- Antal rækker, bundne rækker og rækker med chosen=false for én person, kaldt som p_role UDEN uid (læser, ikke
-- redaktør: redaktøren ser også ikke-offentlige personer, jf. fixtures/kalder-matrix.sql). Uid'en sættes tilbage.
CREATE OR REPLACE FUNCTION pg_temp.fpf_rows(p_person bigint,p_role text DEFAULT 'anon',
  OUT n integer,OUT n_bundet integer,OUT n_ikke_valgt integer) LANGUAGE plpgsql AS $$
DECLARE v_for text:=coalesce(current_setting('request.jwt.claim.sub',true),'');
BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
  EXECUTE format('SET LOCAL ROLE %I',p_role);
  SELECT count(*)::int,
         count(*) FILTER (WHERE r.record_ref IS NOT NULL AND r.record_label IS NOT NULL AND r.citation_label IS NOT NULL)::int,
         count(*) FILTER (WHERE r.chosen IS FALSE)::int
    INTO n,n_bundet,n_ikke_valgt FROM public.public_person_facts(ARRAY[p_person]) r;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub',v_for,true);
END $$;

-- Validatorens reason_code for fixturens item, kaldt som ejer.
CREATE OR REPLACE FUNCTION pg_temp.fpf_reason(m jsonb) RETURNS text LANGUAGE sql AS $$
  SELECT v.reason_code FROM private.validate_interpretation_promotion_items(m->'items') v
$$;
