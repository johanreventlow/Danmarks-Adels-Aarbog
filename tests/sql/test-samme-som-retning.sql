-- Trin 6d-2a: retningen i red_samme_som afgøres af data, når den kan (private.samme_som_data_direction).
-- Opdigtede personer og kilder (negative id'er); en redaktionsaktør, så current_rolle()='redaktion'.
\set ON_ERROR_STOP on

BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/placement-150.sql

-- Kilde med header-kørsel. Uden p_lineage får kilden egen slægt og linje (f150_source); med p_lineage får den et
-- stamtavle-schema, hvis entry 'I' er canonical for den givne linje (en anden udgave af samme slægt).
CREATE OR REPLACE FUNCTION pg_temp.f6d_src(p_source bigint,p_lineage bigint DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_actor uuid:='a1500000-0000-0000-0000-000000000150'; f jsonb; v_slaegt bigint; v_scheme bigint; v_entry bigint;
BEGIN
  IF p_lineage IS NULL THEN
    f:=pg_temp.f150_source(p_source);
  ELSE
    PERFORM pg_temp.f5b_actor(v_actor);
    f:=pg_temp.f5b_source(p_source);
    SELECT slaegt_id INTO v_slaegt FROM public.lineage WHERE id=p_lineage;
    INSERT INTO public.lineage_scheme(slaegt_id,source_id,kind,label) VALUES (v_slaegt,p_source,'stamtavle','6d fixture')
      RETURNING id INTO v_scheme;
    INSERT INTO public.lineage_scheme_entry(scheme_id,slaegt_id,code,label,sort_order)
      VALUES (v_scheme,v_slaegt,'I','I. linje',1) RETURNING id INTO v_entry;
    INSERT INTO public.lineage_scheme_entry_lineage(entry_id,lineage_id,slaegt_id,relation_kind)
      VALUES (v_entry,p_lineage,v_slaegt,'canonical');
    f:=f||jsonb_build_object('source',p_source,'slaegt',v_slaegt,'lineage',p_lineage,'entry',v_entry,'actor',v_actor);
  END IF;
  PERFORM private.write_header_evidence(p_source,(f->>'rend')::uuid,pg_temp.f150_run(),
    jsonb_build_array(pg_temp.f150_h('header_linje',500,'I DEN TESTSKE LINJE')));
  RETURN f;
END $$;

-- Hovedperson-post med accepteret record- og persona-placement på kildens entry 'I'. Returnerer personaen.
CREATE OR REPLACE FUNCTION pg_temp.f6d_place(f jsonb,p_key text,p_person bigint,p_nr int) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE p jsonb; v_obs uuid; v_rp uuid;
BEGIN
  p:=pg_temp.f150_post(f,p_key,p_person,p_nr,1);
  v_obs:=private.header_observation_uuid((f->>'rend')::uuid,'header-2018-20-v1',500);
  v_rp:=private.write_record_placement((p->>'record')::uuid,(f->>'entry')::bigint,
    jsonb_build_object('printed_number',p_nr::text),v_obs,
    jsonb_build_object('rule_version','header-2018-20-v1','header_ids',jsonb_build_object('linje',v_obs)));
  PERFORM private.write_persona_placement((p->>'principal')::uuid,v_rp,(p->>'helpost')::uuid,'{"rule":"test"}');
  RETURN (p->>'principal')::uuid;
END $$;

-- Fremmer kildens egnede items som redaktør (som red_preview/red_promote i test-placement-membership.sql).
CREATE OR REPLACE FUNCTION pg_temp.f6d_promote(f jsonb) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v jsonb; v_n int;
BEGIN
  PERFORM set_config('app.change_set_id','',true);   -- tidligere red_samme_som i transaktionen må ikke blokere promotion
  PERFORM set_config('app.change_seq','',true);
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  SET LOCAL ROLE authenticated;
  v:=public.red_preview_placement_memberships((f->>'source')::bigint);
  v_n:=public.red_promote_placement_memberships((f->>'source')::bigint,v->>'preview_sha256');
  RESET ROLE;
  RETURN v_n;
END $$;

-- samme_som alias → kanonisk, med konklusion (NULL: ingen konklusion).
CREATE OR REPLACE FUNCTION pg_temp.f6d_same(p_alias bigint,p_canon bigint,p_status text) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_id bigint;
BEGIN
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',p_alias,'person',p_canon,'samme_som') RETURNING id INTO v_id;
  IF p_status IS NOT NULL THEN
    INSERT INTO public.conclusion(target_type,target_id,status) VALUES ('relation',v_id,p_status);
  END IF;
  RETURN v_id;
END $$;


-- Hovedperson med gældende K-medlemskab (og K-narrativ, hvis p_text).
CREATE OR REPLACE FUNCTION pg_temp.ov_member(f jsonb,p_key text,p_person bigint,p_nr int,p_text boolean DEFAULT true)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_n bigint;
BEGIN
  PERFORM pg_temp.f6d_place(f,p_key,p_person,p_nr);
  IF pg_temp.f6d_promote(f)<1 THEN RAISE EXCEPTION 'OVERVIEW_MENTION_TEST_FAILED: promotion %',p_person; END IF;
  IF p_text THEN
    INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,tekst)
      VALUES ('person',p_person,(f->>'source')::bigint,'Opdigtet tekst om '||p_person) RETURNING id INTO v_n;
  END IF;
  RETURN v_n;
END $$;

-- Person uden medlemskab med en K-narrativ (oversigtsomtale-kandidat).
CREATE OR REPLACE FUNCTION pg_temp.ov_mention(p_person bigint,p_source bigint,p_levende boolean DEFAULT false)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_n bigint;
BEGIN
  INSERT INTO public.person(id,levende) VALUES (p_person,p_levende) ON CONFLICT DO NOTHING;
  INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,tekst)
    VALUES ('person',p_person,p_source,'Opdigtet omtale af '||p_person) RETURNING id INTO v_n;
  RETURN v_n;
END $$;


-- »Optræder i K« uden gældende medlemskab: ekstern id-række i kilden.
CREATE OR REPLACE FUNCTION pg_temp.sr_appear(p_person bigint,p_source bigint) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.person_external_id(person_id,source_id) VALUES (p_person,p_source) ON CONFLICT DO NOTHING
$$;
CREATE OR REPLACE FUNCTION pg_temp.sr_person(p_person bigint) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.person(id,levende) VALUES (p_person,false) ON CONFLICT DO NOTHING
$$;
-- Kantens retning som 'alias>objekt' for det givne relations-id.
CREATE OR REPLACE FUNCTION pg_temp.sr_dir(p_rel bigint) RETURNS text LANGUAGE sql AS $$
  SELECT subjekt_id||'>'||objekt_id FROM public.relation WHERE id=p_rel
$$;
CREATE OR REPLACE FUNCTION pg_temp.sr_expect(p_name text,p_rel bigint,p_expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF pg_temp.sr_dir(p_rel) IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION 'SAMME_SOM_RETNING_TEST_FAILED: % forventet [%] fik [%]',p_name,p_expected,pg_temp.sr_dir(p_rel);
  END IF;
END $$;
CREATE OR REPLACE FUNCTION pg_temp.sr_as_editor(f jsonb) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  IF public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'SAMME_SOM_RETNING_TEST_FAILED: aktør ikke redaktion'; END IF;
END $$;

DO $data_vender$
DECLARE f jsonb:=pg_temp.f6d_src(-6301); v_rel bigint;
BEGIN
  PERFORM pg_temp.ov_member(f,'I-1',-630101,1);      -- detalje
  PERFORM pg_temp.sr_person(-630102); PERFORM pg_temp.sr_appear(-630102,-6301);   -- oversigt
  PERFORM pg_temp.sr_as_editor(f);
  v_rel:=public.red_samme_som(-630101,-630102);      -- redaktøren angiver detalje → oversigt
  PERFORM pg_temp.sr_expect('data_vender',v_rel,'-630102>-630101');
END $data_vender$;

DO $data_bekraefter$
DECLARE f jsonb:=pg_temp.f6d_src(-6311); v_rel bigint;
BEGIN
  PERFORM pg_temp.ov_member(f,'I-1',-631101,1);
  PERFORM pg_temp.sr_person(-631102); PERFORM pg_temp.sr_appear(-631102,-6311);
  PERFORM pg_temp.sr_as_editor(f);
  v_rel:=public.red_samme_som(-631102,-631101);
  PERFORM pg_temp.sr_expect('data_bekraefter',v_rel,'-631102>-631101');
END $data_bekraefter$;

DO $g3_fallback$
DECLARE f jsonb:=pg_temp.f6d_src(-6321); v_rel bigint;
BEGIN
  PERFORM pg_temp.ov_member(f,'I-1',-632101,1);
  PERFORM pg_temp.sr_person(-632102); PERFORM pg_temp.sr_appear(-632102,-6321);
  PERFORM pg_temp.sr_person(-632103);                -- tredje person (fx 2018-20)
  PERFORM pg_temp.sr_as_editor(f);
  PERFORM public.red_samme_som(-632102,-632103);     -- oversigtspersonen er allerede alias for en anden
  IF (SELECT count(*) FROM private.samme_som_data_direction(-632101,-632102) WHERE alias_id=-632102 AND objekt_id=-632101)<>1 THEN
    RAISE EXCEPTION 'SAMME_SOM_RETNING_TEST_FAILED: g3_fallback datavejen skulle være oversigt>detalje';
  END IF;
  v_rel:=public.red_samme_som(-632101,-632102);      -- datavejen ville afvises af G3 → redaktørens retning
  PERFORM pg_temp.sr_expect('g3_fallback',v_rel,'-632101>-632102');
END $g3_fallback$;

DO $begge_placeret$
DECLARE f jsonb:=pg_temp.f6d_src(-6331); v_rel bigint;
BEGIN
  PERFORM pg_temp.ov_member(f,'I-1',-633101,1,false);
  PERFORM pg_temp.ov_member(f,'I-2',-633102,2,false);
  PERFORM pg_temp.sr_as_editor(f);
  v_rel:=public.red_samme_som(-633101,-633102);
  PERFORM pg_temp.sr_expect('begge_placeret',v_rel,'-633101>-633102');
END $begge_placeret$;

DO $ingen_placeret$
DECLARE f jsonb:=pg_temp.f6d_src(-6341); v_rel bigint;
BEGIN
  PERFORM pg_temp.sr_person(-634101); PERFORM pg_temp.sr_appear(-634101,-6341);
  PERFORM pg_temp.sr_person(-634102); PERFORM pg_temp.sr_appear(-634102,-6341);
  PERFORM pg_temp.sr_as_editor(f);
  v_rel:=public.red_samme_som(-634101,-634102);
  PERFORM pg_temp.sr_expect('ingen_placeret',v_rel,'-634101>-634102');
END $ingen_placeret$;

DO $par_2018_20$
DECLARE f1 jsonb:=pg_temp.f6d_src(-6351); f2 jsonb:=pg_temp.f6d_src(-6352); v_rel bigint;
BEGIN
  PERFORM pg_temp.ov_member(f1,'I-1',-635101,1,false);   -- medlemskab i kilde 1 alene
  PERFORM pg_temp.ov_member(f2,'I-1',-635102,1,false);   -- medlemskab i kilde 2 alene
  PERFORM pg_temp.sr_as_editor(f1);
  v_rel:=public.red_samme_som(-635102,-635101);
  PERFORM pg_temp.sr_expect('2018_20_par',v_rel,'-635102>-635101');
END $par_2018_20$;

DO $modsat_kilder$
DECLARE f1 jsonb:=pg_temp.f6d_src(-6361); f2 jsonb:=pg_temp.f6d_src(-6362); v_rel bigint;
BEGIN
  PERFORM pg_temp.ov_member(f1,'I-1',-636101,1,false);   -- A: medlem i 1, optræder i 2
  PERFORM pg_temp.ov_member(f2,'I-1',-636102,1,false);   -- B: medlem i 2, optræder i 1
  PERFORM pg_temp.sr_appear(-636101,-6362); PERFORM pg_temp.sr_appear(-636102,-6361);
  IF (SELECT count(*) FROM private.samme_som_data_direction(-636101,-636102))<>0 THEN
    RAISE EXCEPTION 'SAMME_SOM_RETNING_TEST_FAILED: modsat_kilder skulle give ingen række';
  END IF;
  PERFORM pg_temp.sr_as_editor(f1);
  v_rel:=public.red_samme_som(-636101,-636102);
  PERFORM pg_temp.sr_expect('modsat_kilder',v_rel,'-636101>-636102');
END $modsat_kilder$;

DO $idempotent$
DECLARE f jsonb:=pg_temp.f6d_src(-6371); v_rel bigint; v_rel2 bigint; v_persona uuid;
  c0 bigint[]; c1 bigint[];
BEGIN
  v_persona:=pg_temp.f6d_place(f,'I-1',-637101,1);
  PERFORM pg_temp.f6d_promote(f);
  PERFORM pg_temp.sr_person(-637102); PERFORM pg_temp.sr_appear(-637102,-6371);
  PERFORM pg_temp.sr_person(-637103); PERFORM pg_temp.sr_person(-637104);
  PERFORM pg_temp.sr_as_editor(f);
  v_rel:=public.red_samme_som(-637101,-637102);
  PERFORM pg_temp.sr_expect('idempotent første',v_rel,'-637102>-637101');
  -- et par uden data: kald i begge rækkefølger
  v_rel2:=public.red_samme_som(-637103,-637104);
  PERFORM pg_temp.sr_expect('idempotent uden data',v_rel2,'-637103>-637104');
  SELECT ARRAY[(SELECT count(*) FROM public.change_set),(SELECT count(*) FROM public.assertion),(SELECT count(*) FROM public.conclusion)] INTO c0;
  IF public.red_samme_som(-637101,-637102)<>v_rel OR public.red_samme_som(-637102,-637101)<>v_rel
     OR public.red_samme_som(-637103,-637104)<>v_rel2 OR public.red_samme_som(-637104,-637103)<>v_rel2 THEN
    RAISE EXCEPTION 'SAMME_SOM_RETNING_TEST_FAILED: idempotent gav nyt relations-id';
  END IF;
  SELECT ARRAY[(SELECT count(*) FROM public.change_set),(SELECT count(*) FROM public.assertion),(SELECT count(*) FROM public.conclusion)] INTO c1;
  IF c0<>c1 THEN RAISE EXCEPTION 'SAMME_SOM_RETNING_TEST_FAILED: idempotent skrev rækker % -> %',c0,c1; END IF;
  -- medlemskabet gøres ugældende (identiteten omafgøres), kaldene er stadig idempotente
  INSERT INTO public.person(id) VALUES (-637199);
  UPDATE private.source_persona_identity SET canonical_person_id=-637199,version=2 WHERE source_persona_id=v_persona;
  IF EXISTS (SELECT 1 FROM private.samme_som_data_direction(-637101,-637102)) THEN
    RAISE EXCEPTION 'SAMME_SOM_RETNING_TEST_FAILED: retning stadig afgjort efter ugyldigt medlemskab';
  END IF;
  IF public.red_samme_som(-637101,-637102)<>v_rel OR public.red_samme_som(-637102,-637101)<>v_rel THEN
    RAISE EXCEPTION 'SAMME_SOM_RETNING_TEST_FAILED: idempotent efter ændret medlemskab gav nyt id';
  END IF;
  SELECT ARRAY[(SELECT count(*) FROM public.change_set),(SELECT count(*) FROM public.assertion),(SELECT count(*) FROM public.conclusion)] INTO c1;
  IF c0<>c1 THEN RAISE EXCEPTION 'SAMME_SOM_RETNING_TEST_FAILED: idempotent efter ændring skrev rækker % -> %',c0,c1; END IF;
END $idempotent$;

DO $acl$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r,'private.samme_som_data_direction(bigint,bigint)','EXECUTE') THEN
      RAISE EXCEPTION 'SAMME_SOM_RETNING_TEST_FAILED: % kan eksekvere samme_som_data_direction',r;
    END IF;
  END LOOP;
  IF NOT has_function_privilege('authenticated','public.red_samme_som(bigint,bigint)','EXECUTE')
     OR has_function_privilege('anon','public.red_samme_som(bigint,bigint)','EXECUTE') THEN
    RAISE EXCEPTION 'SAMME_SOM_RETNING_TEST_FAILED: red_samme_som ACL ændret';
  END IF;
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM * FROM private.samme_som_data_direction(-1,-2);
    RAISE EXCEPTION 'SAMME_SOM_RETNING_TEST_FAILED: anon kunne kalde';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM * FROM private.samme_som_data_direction(-1,-2);
    RAISE EXCEPTION 'SAMME_SOM_RETNING_TEST_FAILED: authenticated kunne kalde';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RESET ROLE;
END $acl$;

SELECT 'SAMME_SOM_RETNING_OK';
ROLLBACK;
