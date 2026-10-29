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
DECLARE f jsonb; r jsonb; v_src2 jsonb; n int; v_dup int; v_order int; v_sl2 bigint; v_lin2 bigint; v_sch2 bigint;
  v_ent2 bigint; v_post2 jsonb; v_obs2 uuid; v_rp2 uuid; v_pp2 uuid; v_state jsonb; v_sha text;
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

  -- (6) to gyldige memberships i samme kilde (to slægter; syntetisk som ejer — promotionen afviser det) ⇒ legacy
  f:=pg_temp.fco_placed(-5231,-523101);
  INSERT INTO public.slaegt(navn,sorteringsnavn,slug,status) VALUES ('5c2 anden','5c2 anden','f5c2-anden','historical')
    RETURNING id INTO v_sl2;
  INSERT INTO public.lineage(slaegt_id,canonical_label,navn) VALUES (v_sl2,'II. linje','5c2 anden linje') RETURNING id INTO v_lin2;
  INSERT INTO public.lineage_scheme(slaegt_id,source_id,kind,label) VALUES (v_sl2,-5231,'stamtavle','5c2 anden') RETURNING id INTO v_sch2;
  INSERT INTO public.lineage_scheme_entry(scheme_id,slaegt_id,code,label,sort_order) VALUES (v_sch2,v_sl2,'II','II. linje',1)
    RETURNING id INTO v_ent2;
  INSERT INTO public.lineage_scheme_entry_lineage(entry_id,lineage_id,slaegt_id,relation_kind) VALUES (v_ent2,v_lin2,v_sl2,'canonical');
  v_post2:=pg_temp.f5b_post(-5231,f,'II-1','Anden Testesen, f. 1650.',ARRAY['Anden Testesen'],-523101,(f->>'actor')::uuid);
  PERFORM private.write_header_evidence(-5231,(f->>'rend')::uuid,pg_temp.f150_run(),
    jsonb_build_array(pg_temp.f150_h('header_linje',600,'II DEN ANDEN LINJE')));
  v_obs2:=private.header_observation_uuid((f->>'rend')::uuid,'header-2018-20-v1',600);
  v_rp2:=private.write_record_placement((v_post2->>'record')::uuid,v_ent2,'{"printed_number":"1"}',v_obs2,
    jsonb_build_object('rule_version','header-2018-20-v1','header_ids',jsonb_build_object('linje',v_obs2)));
  v_pp2:=private.write_persona_placement((v_post2->>'principal')::uuid,v_rp2,(v_post2->>'helpost')::uuid,'{"rule":"test"}');
  v_state:=private.membership_state(v_pp2);
  IF v_state IS NULL THEN RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: (6) ingen membership_state'; END IF;
  v_sha:=private.reimport_canonical_json_sha256(v_state);
  INSERT INTO public.person_lineage_membership(person_id,lineage_id,role,source_basis)
    VALUES (-523101,v_lin2,'member',v_state||jsonb_build_object('state_sha256',v_sha));
  INSERT INTO public.person_slaegt_membership(person_id,slaegt_id,membership_kind,source_basis)
    VALUES (-523101,v_sl2,'agnatic',v_state||jsonb_build_object('state_sha256',v_sha));
  IF NOT private.membership_is_current(-523101,v_lin2) OR NOT private.membership_is_current(-523101,(f->>'lineage')::bigint) THEN
    RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: (6) begge memberships skal være gældende';
  END IF;
  SELECT count(*) INTO n FROM pg_temp.fco_rows(-523101);
  SELECT r2 INTO r FROM pg_temp.fco_rows(-523101) r2;
  IF n<>1 OR r->>'provenance_kind'<>'legacy_external_id' OR r->>'printed_number_label'<>'15' THEN
    RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: (6) to memberships n=% %',n,r;
  END IF;

  -- (7) en membership-række med ugyldigt record_placement_id må ikke vælte RPC'en for alle
  -- (membership_is_current tjekker ikke source_basis' record_placement_id, så rækken er stadig gældende) ⇒ legacy
  f:=pg_temp.fco_placed(-5241,-524101);
  UPDATE public.person_lineage_membership
     SET source_basis=jsonb_set(source_basis,'{record_placement_id}','"ikke-en-uuid"')
   WHERE person_id=-524101;
  IF NOT private.membership_is_current(-524101,(f->>'lineage')::bigint) THEN
    RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: (7) forudsætning: rækken skal stadig være gældende';
  END IF;
  SELECT r2 INTO r FROM pg_temp.fco_rows(-524101) r2;
  IF r->>'provenance_kind'<>'legacy_external_id' THEN RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: (7) ugyldig uuid %',r; END IF;

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
