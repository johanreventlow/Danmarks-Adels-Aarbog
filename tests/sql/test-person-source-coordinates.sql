-- 5c-2 (spec 2026-10-29 §4.2): public_person_source_coordinates. Placement ved præcis én gældende membership i
-- kilden, ellers legacy; persongate; total orden. Kører i frisk-schema-jobbet efter test-placement-membership.sql.
\set ON_ERROR_STOP on

BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/placement-150.sql
\ir fixtures/relation-2a.sql

-- Én placeret hovedperson med legacy nr 15, kuld II, slægtled 3/7 og placement »15a«, kuld tom, slægtled 3/7;
-- membership fremmet gennem redaktions-RPC'en.
CREATE OR REPLACE FUNCTION pg_temp.fco_placed(p_source bigint,p_person bigint) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE f jsonb:=pg_temp.f150_source(p_source); p jsonb; v_obs uuid; v_rp uuid; v_pp uuid; v jsonb;
BEGIN
  p:=pg_temp.f150_post(f,'I-15a',p_person,15,3);
  UPDATE public.person_external_id SET kuld='II',slaegtled_gennem=7 WHERE person_id=p_person AND source_id=p_source;
  PERFORM private.write_header_evidence(p_source,(f->>'rend')::uuid,pg_temp.f150_run(),
    jsonb_build_array(pg_temp.f150_h('header_linje',500,'I DEN TESTSKE LINJE')));
  v_obs:=private.header_observation_uuid((f->>'rend')::uuid,'header-2018-20-v1',500);
  v_rp:=private.write_record_placement((p->>'record')::uuid,(f->>'entry')::bigint,
    '{"printed_number":"15a","generation_local":3,"generation_global":7}',v_obs,
    jsonb_build_object('rule_version','header-2018-20-v1','header_ids',jsonb_build_object('linje',v_obs)));
  v_pp:=private.write_persona_placement((p->>'principal')::uuid,v_rp,(p->>'helpost')::uuid,'{"rule":"test"}');
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  SET LOCAL ROLE authenticated;
  v:=public.red_preview_placement_memberships(p_source);
  PERFORM public.red_promote_placement_memberships(p_source,v->>'preview_sha256');
  RESET ROLE;
  PERFORM set_config('app.change_set_id','',true);
  IF NOT private.membership_is_current(p_person,(f->>'lineage')::bigint) THEN RAISE EXCEPTION 'FCO_FIXTURE: ingen membership'; END IF;
  RETURN f||jsonb_build_object('post',p,'rp',v_rp,'pp',v_pp,'person',p_person);
END $$;

-- Rækkerne for én person som p_role.
CREATE OR REPLACE FUNCTION pg_temp.fco_rows(p_person bigint,p_role text DEFAULT 'anon')
RETURNS SETOF jsonb LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format('SET LOCAL ROLE %I',p_role);
  RETURN QUERY SELECT to_jsonb(r) FROM public.public_person_source_coordinates() r WHERE r.person_id=p_person;
  RESET ROLE;
END $$;

DO $coordinates$
DECLARE f jsonb; r jsonb; v_src2 jsonb; n int; v_dup int; v_order int;
BEGIN
  -- (1) placement: linje fra entryens code, heltal + label, slægtled og kuld fra placementen
  f:=pg_temp.fco_placed(-5201,-520101);
  SELECT r2 INTO r FROM pg_temp.fco_rows(-520101) r2 WHERE (r2->>'source_id')::bigint=-5201;
  IF r->>'provenance_kind'<>'placement' OR r->>'legacy_line_code'<>'I' OR (r->>'printed_number')::int<>15
     OR r->>'printed_number_label'<>'15a' OR (r->>'generation_local')::int<>3 OR (r->>'generation_global')::int<>7
     OR r->>'kuld_label' IS NOT NULL THEN
    RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: placement %',r;
  END IF;
  SELECT count(*) INTO n FROM pg_temp.fco_rows(-520101,'authenticated');
  IF n<>1 THEN RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: authenticated %',n; END IF;

  -- (2) legacy-række i en anden kilde: egen række med legacy-værdier og label = nr::text
  v_src2:=pg_temp.f5b_source(-5209);
  INSERT INTO public.person_external_id(person_id,source_id,linje,nr,kuld) VALUES (-520101,-5209,'V',4,'III');
  SELECT count(*) INTO n FROM pg_temp.fco_rows(-520101);
  SELECT r2 INTO r FROM pg_temp.fco_rows(-520101) r2 WHERE (r2->>'source_id')::bigint=-5209;
  IF n<>2 OR r->>'provenance_kind'<>'legacy_external_id' OR r->>'legacy_line_code'<>'V'
     OR (r->>'printed_number')::int<>4 OR r->>'printed_number_label'<>'4' OR r->>'kuld_label'<>'III' THEN
    RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: anden kilde n=% %',n,r;
  END IF;

  -- (3) membership gjort ugældende (ny identitetsversion) ⇒ legacy
  f:=pg_temp.fco_placed(-5211,-521101);
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  PERFORM pg_temp.f2a_event_for_state((f->'post'->>'principal')::uuid);
  SELECT version INTO n FROM private.source_persona_identity WHERE source_persona_id=(f->'post'->>'principal')::uuid;
  PERFORM private.decide_source_persona_identity((f->'post'->>'principal')::uuid,-521101,n,'accepted',
    '{"basis":"web_detail","note":"5c2 ny version"}','human');
  IF private.membership_is_current(-521101,(f->>'lineage')::bigint) THEN
    RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: (3) membership stadig gældende';
  END IF;
  SELECT r2 INTO r FROM pg_temp.fco_rows(-521101) r2;
  IF r->>'provenance_kind'<>'legacy_external_id' OR r->>'printed_number_label'<>'15' OR r->>'kuld_label'<>'II' THEN
    RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: ugældende %',r;
  END IF;

  -- (4) gate: levende og privat ⇒ 0, som anon og authenticated
  f:=pg_temp.fco_placed(-5221,-522101);
  UPDATE public.person SET levende=true WHERE id=-522101;
  IF (SELECT count(*) FROM pg_temp.fco_rows(-522101))<>0 OR (SELECT count(*) FROM pg_temp.fco_rows(-522101,'authenticated'))<>0 THEN
    RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: levende';
  END IF;
  UPDATE public.person SET levende=false,privat=true WHERE id=-522101;
  IF (SELECT count(*) FROM pg_temp.fco_rows(-522101))<>0 OR (SELECT count(*) FROM pg_temp.fco_rows(-522101,'authenticated'))<>0 THEN
    RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: privat';
  END IF;

  -- (5) total orden: (person_id, source_id) entydig og sorteret
  SET LOCAL ROLE anon;
  SELECT count(*)-count(DISTINCT (r3.person_id,r3.source_id)) INTO v_dup FROM public.public_person_source_coordinates() r3;
  SELECT count(*) INTO v_order FROM (
    SELECT r3.person_id,r3.source_id,
           lag(r3.person_id) OVER () AS pp,lag(r3.source_id) OVER () AS ps
      FROM public.public_person_source_coordinates() r3) x
   WHERE (x.pp,x.ps) > (x.person_id,x.source_id);
  RESET ROLE;
  IF v_dup<>0 OR v_order<>0 THEN RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: orden dup=% bagud=%',v_dup,v_order; END IF;

  RAISE NOTICE 'OK: public_person_source_coordinates';
END $coordinates$;
ROLLBACK;
