-- 5c-2 (spec 2026-10-29 §4.2): public_person_source_coordinates. Placement ved præcis én gældende membership i
-- kilden, ellers legacy; persongate; total orden. Kører i frisk-schema-jobbet efter test-placement-membership.sql.
\set ON_ERROR_STOP on

BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/placement-150.sql
\ir fixtures/relation-2a.sql
\ir fixtures/kalder-matrix.sql

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

-- Rækkerne for én person som p_role uden uid (læser; redaktøren ser mere, jf. fixtures/kalder-matrix.sql).
-- Uid'en sættes tilbage.
CREATE OR REPLACE FUNCTION pg_temp.fco_rows(p_person bigint,p_role text DEFAULT 'anon')
RETURNS SETOF jsonb LANGUAGE plpgsql AS $$
DECLARE v_for text:=coalesce(current_setting('request.jwt.claim.sub',true),'');
BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
  EXECUTE format('SET LOCAL ROLE %I',p_role);
  RETURN QUERY SELECT to_jsonb(r) FROM public.public_person_source_coordinates() r WHERE r.person_id=p_person;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub',v_for,true);
END $$;

DO $coordinates$
DECLARE f jsonb; r jsonb; v_src2 jsonb; n int; v_dup int; v_order int; v_sl2 bigint; v_lin2 bigint; v_sch2 bigint;
  v_ent2 bigint; v_post2 jsonb; v_obs2 uuid; v_rp2 uuid; v_pp2 uuid; v_state jsonb; v_sha text;
BEGIN
  PERFORM pg_temp.km_kaldere();
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

  -- Kodereview 36 P2: den samlede funktion er præcis de gamle rækker (samme felter, samme orden) som ét jsonb-array,
  -- både for ejeren og for anon.
  FOR i IN 1..2 LOOP
    IF i=2 THEN SET LOCAL ROLE anon; END IF;
    IF public.public_person_source_coordinates_samlet() IS DISTINCT FROM (
         SELECT coalesce(jsonb_agg(to_jsonb(o)-'ordinality' ORDER BY o.ordinality),'[]'::jsonb)
           FROM public.public_person_source_coordinates() WITH ORDINALITY o) THEN
      RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: samlet afviger fra rækkefunktionen (%)',CASE i WHEN 1 THEN 'ejer' ELSE 'anon' END;
    END IF;
    RESET ROLE;
  END LOOP;

  -- Redaktøren ser levende (decisions 2026-11-13): fire kaldere × personstatus, både placement-grenen (-528101) og
  -- legacy-grenen uden placement (-528102). Kun redaktionen ser ikke-offentlige personers koordinater.
  f:=pg_temp.fco_placed(-5281,-528101);
  INSERT INTO public.person(id,levende,privat,status) VALUES (-528102,false,false,'co');
  INSERT INTO public.person_external_id(person_id,source_id,linje,nr) VALUES (-528102,-5281,'V',9);
  PERFORM pg_temp.km_forvent('koordinater afdød',
    'SELECT * FROM public.public_person_source_coordinates() WHERE person_id IN (-528101,-528102)',2,2);
  PERFORM pg_temp.km_forvent('koordinater afdød, samlet',
    'SELECT e FROM jsonb_array_elements(public.public_person_source_coordinates_samlet()) e WHERE (e->>''person_id'')::bigint IN (-528101,-528102)',2,2);
  UPDATE public.person SET levende=true WHERE id IN (-528101,-528102);
  PERFORM pg_temp.km_forvent('koordinater levende',
    'SELECT * FROM public.public_person_source_coordinates() WHERE person_id IN (-528101,-528102)',0,2);
  PERFORM pg_temp.km_forvent('koordinater levende, samlet',
    'SELECT e FROM jsonb_array_elements(public.public_person_source_coordinates_samlet()) e WHERE (e->>''person_id'')::bigint IN (-528101,-528102)',0,2);
  PERFORM pg_temp.km_forvent('koordinater levende, placement',
    'SELECT * FROM public.public_person_source_coordinates() WHERE person_id=-528101 AND provenance_kind=''placement''',0,1);
  UPDATE public.person SET levende=false,privat=true WHERE id IN (-528101,-528102);
  PERFORM pg_temp.km_forvent('koordinater privat',
    'SELECT * FROM public.public_person_source_coordinates() WHERE person_id IN (-528101,-528102)',0,2);
  PERFORM pg_temp.km_forvent('koordinater privat, samlet',
    'SELECT e FROM jsonb_array_elements(public.public_person_source_coordinates_samlet()) e WHERE (e->>''person_id'')::bigint IN (-528101,-528102)',0,2);
  UPDATE public.person SET privat=false,staged=true WHERE id IN (-528101,-528102);
  PERFORM pg_temp.km_forvent('koordinater staged',
    'SELECT * FROM public.public_person_source_coordinates() WHERE person_id IN (-528101,-528102)',0,2);
  UPDATE public.person SET staged=false,levende=NULL WHERE id IN (-528101,-528102);
  PERFORM pg_temp.km_forvent('koordinater levende NULL',
    'SELECT * FROM public.public_person_source_coordinates() WHERE person_id IN (-528101,-528102)',0,2);
  UPDATE public.person SET levende=false WHERE id IN (-528101,-528102);

  RAISE NOTICE 'OK: public_person_source_coordinates';
END $coordinates$;

-- Trin 6d-1 (afgørelse 4b), skærpet i 6e-2: kildegaten. En kilde bruger placement-koordinater kun, når ingen to af dens
-- gældende membership-placements deler (entry, slægtled, kuld, trykt nummer), med NULL som ens. Ellers falder alle
-- kildens rækker til legacy.

-- Kilde med entry 'I' og header-kørsel (som f6d_src i test-membership-component.sql).
CREATE OR REPLACE FUNCTION pg_temp.fco_src(p_source bigint) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE f jsonb:=pg_temp.f150_source(p_source);
BEGIN
  PERFORM private.write_header_evidence(p_source,(f->>'rend')::uuid,pg_temp.f150_run(),
    jsonb_build_array(pg_temp.f150_h('header_linje',500,'I DEN TESTSKE LINJE')));
  RETURN f;
END $$;

-- Hovedperson-post (legacy nr p_nr) med record- og persona-placement på entry 'I' og trykt nummer p_printed (NULL:
-- intet nummer, som 1939's stamfædre).
CREATE OR REPLACE FUNCTION pg_temp.fco_place(f jsonb,p_key text,p_person bigint,p_nr int,p_printed text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE p jsonb; v_obs uuid; v_rp uuid;
BEGIN
  p:=pg_temp.f150_post(f,p_key,p_person,p_nr,1);
  v_obs:=private.header_observation_uuid((f->>'rend')::uuid,'header-2018-20-v1',500);
  v_rp:=private.write_record_placement((p->>'record')::uuid,(f->>'entry')::bigint,
    jsonb_strip_nulls(jsonb_build_object('printed_number',p_printed)),v_obs,
    jsonb_build_object('rule_version','header-2018-20-v1','header_ids',jsonb_build_object('linje',v_obs)));
  PERFORM private.write_persona_placement((p->>'principal')::uuid,v_rp,(p->>'helpost')::uuid,'{"rule":"test"}');
END $$;

-- Fremmer kildens egnede items som redaktør; returnerer antal fremmede.
CREATE OR REPLACE FUNCTION pg_temp.fco_promote(f jsonb) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v jsonb; v_n int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  SET LOCAL ROLE authenticated;
  v:=public.red_preview_placement_memberships((f->>'source')::bigint);
  v_n:=public.red_promote_placement_memberships((f->>'source')::bigint,v->>'preview_sha256');
  RESET ROLE;
  PERFORM set_config('app.change_set_id','',true);
  RETURN v_n;
END $$;

-- Én persons række i kilden; fejler hvis personen ikke har netop én gældende membership.
CREATE OR REPLACE FUNCTION pg_temp.fco_row(f jsonb,p_person bigint) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb; n int;
BEGIN
  IF NOT private.membership_is_current(p_person,(f->>'lineage')::bigint) THEN
    RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: % har ingen gældende membership',p_person;
  END IF;
  SELECT count(*),min(r2::text)::jsonb INTO n,r FROM pg_temp.fco_rows(p_person) r2
   WHERE (r2->>'source_id')::bigint=(f->>'source')::bigint;
  IF n<>1 THEN RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: % har % rækker',p_person,n; END IF;
  RETURN r;
END $$;

DO $laeser_entydig$
DECLARE f jsonb; a jsonb; b jsonb;
BEGIN
  -- Entydig kilde (forskellige numre i samme entry) ⇒ placement, som i dag.
  f:=pg_temp.fco_src(-5251);
  PERFORM pg_temp.fco_place(f,'I-7',-525101,7,'7');
  PERFORM pg_temp.fco_place(f,'I-8',-525102,8,'8a');
  IF pg_temp.fco_promote(f)<>2 THEN RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: entydig: forventede 2 fremmede'; END IF;
  a:=pg_temp.fco_row(f,-525101); b:=pg_temp.fco_row(f,-525102);
  IF a->>'provenance_kind'<>'placement' OR a->>'printed_number_label'<>'7' OR (a->>'printed_number')::int<>7
     OR b->>'provenance_kind'<>'placement' OR b->>'printed_number_label'<>'8a' OR (b->>'printed_number')::int<>8 THEN
    RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: entydig % %',a,b;
  END IF;
  RAISE NOTICE 'OK: laeser_entydig';
END $laeser_entydig$;

DO $laeser_1939$
DECLARE f jsonb; a jsonb; b jsonb; c jsonb; g jsonb;
BEGIN
  -- To placements i samme entry med samme nummer ⇒ alle kildens rækker legacy, også en tredje med eget nummer.
  f:=pg_temp.fco_src(-5261);
  PERFORM pg_temp.fco_place(f,'I-3',-526101,3,'3');
  PERFORM pg_temp.fco_place(f,'I-3b',-526102,30,'3');
  PERFORM pg_temp.fco_place(f,'I-4',-526103,4,'4');
  IF pg_temp.fco_promote(f)<>3 THEN RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: 1939: forventede 3 fremmede'; END IF;
  a:=pg_temp.fco_row(f,-526101); b:=pg_temp.fco_row(f,-526102); c:=pg_temp.fco_row(f,-526103);
  IF a->>'provenance_kind'<>'legacy_external_id' OR a->>'printed_number_label'<>'3'
     OR b->>'provenance_kind'<>'legacy_external_id' OR b->>'printed_number_label'<>'30'
     OR c->>'provenance_kind'<>'legacy_external_id' OR c->>'printed_number_label'<>'4' THEN
    RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: 1939 % % %',a,b,c;
  END IF;
  -- Gaten er pr. kilde: en entydig kilde ved siden af beholder placement.
  g:=pg_temp.fco_src(-5262);
  PERFORM pg_temp.fco_place(g,'I-3',-526201,3,'3');
  IF pg_temp.fco_promote(g)<>1 THEN RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: 1939: nabokilde ikke fremmet'; END IF;
  a:=pg_temp.fco_row(g,-526201);
  IF a->>'provenance_kind'<>'placement' THEN RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: 1939 nabokilde %',a; END IF;
  RAISE NOTICE 'OK: laeser_1939';
END $laeser_1939$;

DO $laeser_null_nummer$
DECLARE f jsonb; a jsonb; b jsonb;
BEGIN
  -- 6e-2: én placement uden trykt nummer (stamfader), alene i sin gruppe, er entydig ⇒ placement med NULL nr., og den
  -- nummererede beholder også placement (før 6e-2 faldt hele kilden til legacy).
  f:=pg_temp.fco_src(-5271);
  PERFORM pg_temp.fco_place(f,'I-0',-527101,1,NULL);
  PERFORM pg_temp.fco_place(f,'I-2',-527102,2,'2');
  IF pg_temp.fco_promote(f)<>2 THEN RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: null_nummer: forventede 2 fremmede'; END IF;
  IF (SELECT rp.printed_number FROM public.person_lineage_membership plm
        JOIN private.source_record_placement rp ON rp.id=(plm.source_basis->>'record_placement_id')::uuid
       WHERE plm.person_id=-527101) IS NOT NULL THEN
    RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: null_nummer: forudsætning: placementen skal mangle nummer';
  END IF;
  a:=pg_temp.fco_row(f,-527101); b:=pg_temp.fco_row(f,-527102);
  IF a->>'provenance_kind'<>'placement' OR a->'printed_number_label'<>'null'::jsonb OR a->'printed_number'<>'null'::jsonb
     OR b->>'provenance_kind'<>'placement' OR b->>'printed_number_label'<>'2' THEN
    RAISE EXCEPTION 'PERSON_COORDINATES_TEST_FAILED: null_nummer % %',a,b;
  END IF;
  RAISE NOTICE 'OK: laeser_null_nummer';
END $laeser_null_nummer$;
ROLLBACK;
