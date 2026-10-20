-- Trin 5b 2b-iii: fixtures for børnehenvisninger oven på relation-5b.sql og relation-2a.sql. Kun opdigtede navne.
-- Forælder -5701 med post V-1 og børn -5702..-5704 med egne poster V-2..V-4 (kuld V, lokalt slægtled 2).
CREATE OR REPLACE FUNCTION pg_temp.fc_setup(p_raw text,p_actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE s jsonb; pa jsonb; c jsonb; v_fam bigint; i int;
BEGIN
  INSERT INTO person(id,levende,privat,status,koen) VALUES (-5701,false,false,'2b3','mand'),(-5705,false,false,'2b3','kvinde');
  INSERT INTO person(id,levende,privat,status,koen) SELECT -5700-g,false,false,'2b3','mand' FROM generate_series(2,4) g;
  s:=pg_temp.f5b_source(-5701);
  pa:=pg_temp.f5b_post(-5701,s,'V-1','Ole Alfa. '||p_raw,ARRAY['Ole Alfa.',p_raw],-5701,p_actor);
  INSERT INTO person_external_id(person_id,source_id,linje,nr,record_key,kuld,slaegtled_lokal)
    VALUES (-5701,-5701,'V',1,'V-1','V',1);
  FOR i IN 2..4 LOOP
    PERFORM pg_temp.f5b_post(-5701,s,'V-'||i,'Barn '||i||' Alfa.',ARRAY['Barn '||i||' Alfa.'],-5700-i,p_actor);
    INSERT INTO person_external_id(person_id,source_id,linje,nr,record_key,kuld,slaegtled_lokal)
      VALUES (-5700-i,-5701,'V',i,'V-'||i,'V',2);
  END LOOP;
  v_fam:=pg_temp.f5b_family(-5701,-5705,1);
  INSERT INTO family_member(family_id,person_id,rolle) SELECT v_fam,-5700-g,'barn' FROM generate_series(2,4) g;
  -- identity_state_has_event er en udskudt constraint-trigger; hver accepteret identitet skal have sit event.
  PERFORM pg_temp.f2a_event_for_state(sp.id) FROM private.source_persona sp WHERE sp.source_id=-5701;
  c:=pg_temp.f5b_claim(-5701,s,'relation.child',(pa->'clauses'->>1)::uuid,p_raw);
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((c->>'key')::uuid,'principal',1,(pa->>'principal')::uuid,0,'relation_persona',gen_random_uuid());
  RETURN jsonb_build_object('claim',c,'family',v_fam,'source',s,'post',pa);
END $$;

-- Arkets kontekst (human_sheet) for linje 1.
CREATE OR REPLACE FUNCTION pg_temp.fc_ctx() RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('basis','human_sheet','sheet_sha256',repeat('a',64),'rows_sha256',repeat('b',64),'line',1) $$;

-- Kører red_afgoer_relation_interpretation som redaktion og returnerer fejlkoden eller 'OK'.
CREATE OR REPLACE FUNCTION pg_temp.fc_decide(p_key uuid,p_ver int,p_action text,p_fam bigint,p_ctx jsonb,p_actor uuid)
RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM red_afgoer_relation_interpretation(p_key,p_ver,p_action,p_fam,'test',p_ctx);
  RESET ROLE;
  RETURN 'OK';
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  RETURN split_part(SQLERRM,':',1);
END $$;

-- Ét regeltilfælde: opsætning med p_raw, derefter p_sql (kan være ''), og reglens udfald som jsonb.
CREATE OR REPLACE FUNCTION pg_temp.fc_rule(p_raw text,p_sql text,p_actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE f jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(p_actor);
  f:=pg_temp.fc_setup(p_raw,p_actor);
  IF p_sql<>'' THEN EXECUTE p_sql; END IF;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  RETURN private.relation_child_rule((f->'claim'->>'id')::uuid)||jsonb_build_object('_claim',f->'claim');
END $$;
