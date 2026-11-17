-- Real other-principal / P-as-spouse promotion, same builders as purge_binding.
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
CREATE FUNCTION pg_temp.r39() RETURNS void LANGUAGE plpgsql AS $$
DECLARE s bigint; src jsonb; m jsonb; pv jsonb; i uuid; items jsonb;
BEGIN
  s:=nextval(pg_get_serial_sequence('public.source','id'));
  src:=pg_temp.f5b_source(s);
  m:=pg_temp.f2a_marriage(s,src,'PURGE-R39',purge_test.id('anden_partner'),purge_test.id('P'),
    'a2a00000-0000-4000-8000-00000000a001',2,2,false);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  pv:=public.red_preview_relation_decisions(s);
  IF public.red_decide_relation_interpretations(s,pv->>'set_sha256')<>1 THEN RAISE EXCEPTION 'TEST_R39_DECIDE'; END IF;
  SELECT id INTO STRICT i FROM private.interpretation_current WHERE interpretation_key=(m->'claim'->>'key')::uuid;
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',i::text,'family_id',purge_test.id('fam_keep')));
  pv:=public.red_preview_relation_promotions(s,items);
  PERFORM public.red_promote_relation_interpretations_batch(s,items,pv->>'preview_sha256');
  INSERT INTO purge_test.r39 SELECT id,private.relation_binding_state_sha256(i) FROM private.interpretation_promotion
    WHERE interpretation_id=i AND target_type='family';
END $$;
SELECT pg_temp.r39();
