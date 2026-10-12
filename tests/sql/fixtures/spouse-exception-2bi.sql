-- Trin 5b 2b-i Task 5: data til arkets ende-til-ende-test. Committes i en engangsbase.
\set ON_ERROR_STOP on
BEGIN;
\ir relation-5b.sql
\ir relation-2a.sql
\ir relation-2bi.sql
DO $spouse_sheet_fixture$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b0501'; s jsonb; s1 jsonb; s2 jsonb; s3 jsonb; o1 jsonb; o2 jsonb; pv jsonb;
  v_items jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status,visning_navn) SELECT g,false,false,'2bi','P'||abs(g) FROM generate_series(-21540,-21501) g;
  s:=pg_temp.f5b_source(-21501);
  s1:=pg_temp.f2bi_open_marriage(-21501,s,'E-1',-21501,-21502,v_actor,1,1);
  s2:=pg_temp.f2bi_open_marriage(-21501,s,'E-2',-21503,-21504,v_actor,1,1);
  s3:=pg_temp.f2bi_open_marriage(-21501,s,'E-3',-21511,-21512,v_actor,1,1);   -- til koe_imellem (kandidat ≠ partner nu; se nedenfor)
  o1:=pg_temp.f2a_marriage(-21501,s,'E-4',-21505,-21506,v_actor,2,1);
  o2:=pg_temp.f2a_marriage(-21501,s,'E-5',-21507,-21508,v_actor,3,1);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(-21501);
  PERFORM red_decide_relation_interpretations(-21501,pv->>'set_sha256');
  RESET ROLE;   -- elementerne bygges som ejer (private)
  SELECT jsonb_agg(jsonb_build_object('interpretation_id',ic.id::text,'family_id',(x->>'family')::bigint))
    INTO v_items FROM (VALUES (o1),(o2)) v(x)
    JOIN private.interpretation_current ic ON ic.interpretation_key=(x->'claim'->>'key')::uuid;
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-21501,v_items);
  PERFORM red_promote_relation_interpretations_batch(-21501,v_items,pv->>'preview_sha256');
  RESET ROLE;
  -- S1 og S2: kandidat nr. 1 = partneren; S3: kandidat nr. 1 = partneren (bruges af koe_imellem efter arket)
  PERFORM pg_temp.f2bi_candidates(-21501,v_actor,jsonb_build_array(
    jsonb_build_object('persona',s1->>'spouse_persona','person',-21502,'rank',1),
    jsonb_build_object('persona',s2->>'spouse_persona','person',-21504,'rank',1),
    jsonb_build_object('persona',s3->>'spouse_persona','person',-21512,'rank',1)));
END $spouse_sheet_fixture$;
COMMIT;
