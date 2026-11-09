-- Trin 6d-1 (B6 afledt): medlemskabstilstand pr. identitetskomponent. En komponent er lukningen over person↔person-
-- samme_som med afklaret konklusion; kun gældende medlemskaber tæller. Opdigtede personer og kilder (negative id'er).
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

-- Komponentrækken, der indeholder personen (NULL hvis ingen); fejler hvis personen står i flere.
CREATE OR REPLACE FUNCTION pg_temp.f6d_comp(p_person bigint) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb; n int;
BEGIN
  SELECT count(*),min(to_jsonb(c)::text)::jsonb INTO n,v FROM private.membership_component_states() c
   WHERE p_person=ANY(c.members);
  IF n>1 THEN RAISE EXCEPTION 'MEMBERSHIP_COMPONENT_TEST_FAILED: % i % komponenter',p_person,n; END IF;
  RETURN v;
END $$;

DO $bekraeftet$
DECLARE f1 jsonb:=pg_temp.f6d_src(-1641); f3 jsonb; c jsonb;
BEGIN
  PERFORM pg_temp.f6d_place(f1,'I-1',-164101,1);
  f3:=pg_temp.f6d_src(-1643,(f1->>'lineage')::bigint);
  PERFORM pg_temp.f6d_place(f3,'I-1',-164103,1);
  IF pg_temp.f6d_promote(f1)<>1 OR pg_temp.f6d_promote(f3)<>1 THEN
    RAISE EXCEPTION 'MEMBERSHIP_COMPONENT_TEST_FAILED: opsætning';
  END IF;
  PERFORM pg_temp.f6d_same(-164103,-164101,'afklaret');
  c:=pg_temp.f6d_comp(-164101);
  IF c IS NULL OR c IS DISTINCT FROM pg_temp.f6d_comp(-164103)
     OR (c->>'component_root')::bigint<>-164103 OR c->'members'<>'[-164103,-164101]'::jsonb
     OR c->>'state'<>'corroborated' OR c->'lineage_ids'<>jsonb_build_array((f1->>'lineage')::bigint)
     OR c->'source_ids'<>'[-1643,-1641]'::jsonb OR (c->>'same_source_duplicate')::boolean THEN
    RAISE EXCEPTION 'MEMBERSHIP_COMPONENT_TEST_FAILED: bekræftet %',c;
  END IF;
END $bekraeftet$;

DO $konflikt_uroert$
DECLARE f1 jsonb:=pg_temp.f6d_src(-1651); f3 jsonb:=pg_temp.f6d_src(-1653); c jsonb; v_before text; v_after text;
BEGIN
  PERFORM pg_temp.f6d_place(f1,'I-1',-165101,1);
  PERFORM pg_temp.f6d_place(f3,'I-1',-165103,1);
  PERFORM pg_temp.f6d_promote(f1); PERFORM pg_temp.f6d_promote(f3);
  PERFORM pg_temp.f6d_same(-165103,-165101,'afklaret');
  SELECT md5(coalesce((SELECT string_agg(to_jsonb(l)::text,'|' ORDER BY l.person_id,l.lineage_id)
                         FROM public.person_lineage_membership l WHERE l.person_id IN (-165101,-165103)),'')
           ||coalesce((SELECT string_agg(to_jsonb(m)::text,'|' ORDER BY m.person_id,m.slaegt_id)
                         FROM public.person_slaegt_membership m WHERE m.person_id IN (-165101,-165103)),'')
           ||(SELECT count(*) FROM public.change_event)::text)
    INTO v_before;
  c:=pg_temp.f6d_comp(-165101);
  IF c IS NULL OR c->>'state'<>'conflict' OR c->'members'<>'[-165103,-165101]'::jsonb
     OR c->'lineage_ids'<>(SELECT jsonb_agg(x ORDER BY x) FROM unnest(ARRAY[(f1->>'lineage')::bigint,(f3->>'lineage')::bigint]) x)
     OR c->'source_ids'<>'[-1653,-1651]'::jsonb OR (c->>'same_source_duplicate')::boolean THEN
    RAISE EXCEPTION 'MEMBERSHIP_COMPONENT_TEST_FAILED: konflikt %',c;
  END IF;
  SELECT md5(coalesce((SELECT string_agg(to_jsonb(l)::text,'|' ORDER BY l.person_id,l.lineage_id)
                         FROM public.person_lineage_membership l WHERE l.person_id IN (-165101,-165103)),'')
           ||coalesce((SELECT string_agg(to_jsonb(m)::text,'|' ORDER BY m.person_id,m.slaegt_id)
                         FROM public.person_slaegt_membership m WHERE m.person_id IN (-165101,-165103)),'')
           ||(SELECT count(*) FROM public.change_event)::text)
    INTO v_after;
  IF v_before IS DISTINCT FROM v_after OR (SELECT count(*) FROM public.person_lineage_membership
                                             WHERE person_id IN (-165101,-165103))<>2 THEN
    RAISE EXCEPTION 'MEMBERSHIP_COMPONENT_TEST_FAILED: konflikten ændrede tabellerne';
  END IF;
END $konflikt_uroert$;

DO $enkelt$
DECLARE f1 jsonb:=pg_temp.f6d_src(-1661); c jsonb;
BEGIN
  PERFORM pg_temp.f6d_place(f1,'I-1',-166101,1);
  PERFORM pg_temp.f6d_promote(f1);
  c:=pg_temp.f6d_comp(-166101);
  IF c IS NULL OR (c->>'component_root')::bigint<>-166101 OR c->'members'<>'[-166101]'::jsonb OR c->>'state'<>'single'
     OR c->'lineage_ids'<>jsonb_build_array((f1->>'lineage')::bigint) OR c->'source_ids'<>'[-1661]'::jsonb
     OR (c->>'same_source_duplicate')::boolean THEN
    RAISE EXCEPTION 'MEMBERSHIP_COMPONENT_TEST_FAILED: enkelt %',c;
  END IF;
  -- En person uden medlemskab og uden identitetslink er ingen komponent; to uden medlemskab er 'none'.
  INSERT INTO public.person(id) VALUES (-166199),(-166198),(-166197);
  PERFORM pg_temp.f6d_same(-166198,-166197,'afklaret');
  c:=pg_temp.f6d_comp(-166197);
  IF pg_temp.f6d_comp(-166199) IS NOT NULL OR c IS NULL OR c->'members'<>'[-166198,-166197]'::jsonb
     OR c->>'state'<>'none' OR c->'lineage_ids'<>'[]'::jsonb OR c->'source_ids'<>'[]'::jsonb
     OR (c->>'same_source_duplicate')::boolean THEN
    RAISE EXCEPTION 'MEMBERSHIP_COMPONENT_TEST_FAILED: none %',c;
  END IF;
END $enkelt$;

DO $ikke_afklaret$
DECLARE f1 jsonb:=pg_temp.f6d_src(-1671); f3 jsonb; f5 jsonb; c jsonb;
BEGIN
  PERFORM pg_temp.f6d_place(f1,'I-1',-167101,1);
  f3:=pg_temp.f6d_src(-1673,(f1->>'lineage')::bigint);
  PERFORM pg_temp.f6d_place(f3,'I-1',-167103,1);
  f5:=pg_temp.f6d_src(-1675,(f1->>'lineage')::bigint);
  PERFORM pg_temp.f6d_place(f5,'I-1',-167105,1);
  PERFORM pg_temp.f6d_promote(f1); PERFORM pg_temp.f6d_promote(f3); PERFORM pg_temp.f6d_promote(f5);
  -- Omstridt konklusion og ingen konklusion: ingen af kanterne binder komponenten.
  PERFORM pg_temp.f6d_same(-167103,-167101,'omstridt');
  PERFORM pg_temp.f6d_same(-167105,-167101,NULL);
  c:=pg_temp.f6d_comp(-167101);
  IF c IS NULL OR c->'members'<>'[-167101]'::jsonb OR c->>'state'<>'single' OR c->'source_ids'<>'[-1671]'::jsonb
     OR pg_temp.f6d_comp(-167103)->'members'<>'[-167103]'::jsonb OR pg_temp.f6d_comp(-167103)->>'state'<>'single'
     OR pg_temp.f6d_comp(-167105)->'members'<>'[-167105]'::jsonb THEN
    RAISE EXCEPTION 'MEMBERSHIP_COMPONENT_TEST_FAILED: ikke afklaret %',c;
  END IF;
  -- Afklares den omstridte, smelter -167101 og -167103 sammen (bekræftet); -167105 står stadig alene.
  UPDATE public.conclusion SET status='afklaret' WHERE target_type='relation'
     AND target_id=(SELECT id FROM public.relation WHERE rolle='samme_som' AND subjekt_id=-167103);
  c:=pg_temp.f6d_comp(-167101);
  IF c->'members'<>'[-167103,-167101]'::jsonb OR c->>'state'<>'corroborated'
     OR pg_temp.f6d_comp(-167105)->'members'<>'[-167105]'::jsonb THEN
    RAISE EXCEPTION 'MEMBERSHIP_COMPONENT_TEST_FAILED: afklaret efter omafgørelse %',c;
  END IF;
END $ikke_afklaret$;

DO $samme_kilde_dublet$
DECLARE f1 jsonb:=pg_temp.f6d_src(-1681); c jsonb;
BEGIN
  PERFORM pg_temp.f6d_place(f1,'I-1',-168101,1);
  PERFORM pg_temp.f6d_place(f1,'I-2',-168102,2);
  IF pg_temp.f6d_promote(f1)<>2 THEN RAISE EXCEPTION 'MEMBERSHIP_COMPONENT_TEST_FAILED: opsætning dublet'; END IF;
  PERFORM pg_temp.f6d_same(-168101,-168102,'afklaret');
  c:=pg_temp.f6d_comp(-168102);
  IF c IS NULL OR (c->>'component_root')::bigint<>-168102 OR c->'members'<>'[-168102,-168101]'::jsonb
     OR c->>'state'<>'single' OR c->'source_ids'<>'[-1681]'::jsonb
     OR c->'lineage_ids'<>jsonb_build_array((f1->>'lineage')::bigint)
     OR NOT (c->>'same_source_duplicate')::boolean THEN
    RAISE EXCEPTION 'MEMBERSHIP_COMPONENT_TEST_FAILED: samme kilde %',c;
  END IF;
END $samme_kilde_dublet$;

DO $ikke_gaeldende$
DECLARE f1 jsonb:=pg_temp.f6d_src(-1691); f3 jsonb; v_persona uuid; c jsonb;
BEGIN
  PERFORM pg_temp.f6d_place(f1,'I-1',-169101,1);
  f3:=pg_temp.f6d_src(-1693,(f1->>'lineage')::bigint);
  v_persona:=pg_temp.f6d_place(f3,'I-1',-169103,1);
  PERFORM pg_temp.f6d_promote(f1); PERFORM pg_temp.f6d_promote(f3);
  PERFORM pg_temp.f6d_same(-169103,-169101,'afklaret');
  IF pg_temp.f6d_comp(-169101)->>'state'<>'corroborated' THEN
    RAISE EXCEPTION 'MEMBERSHIP_COMPONENT_TEST_FAILED: opsætning ikke gældende';
  END IF;
  -- Identiteten afgøres igen til en anden person: -169103's medlemskab er ikke længere gældende og tæller ikke.
  INSERT INTO public.person(id) VALUES (-169199);
  UPDATE private.source_persona_identity SET canonical_person_id=-169199,version=2 WHERE source_persona_id=v_persona;
  IF private.membership_is_current(-169103,(f1->>'lineage')::bigint) THEN
    RAISE EXCEPTION 'MEMBERSHIP_COMPONENT_TEST_FAILED: medlemskabet stadig gældende';
  END IF;
  c:=pg_temp.f6d_comp(-169101);
  IF c IS NULL OR c->'members'<>'[-169103,-169101]'::jsonb OR c->>'state'<>'single'
     OR c->'source_ids'<>'[-1691]'::jsonb OR (c->>'same_source_duplicate')::boolean THEN
    RAISE EXCEPTION 'MEMBERSHIP_COMPONENT_TEST_FAILED: ikke gældende %',c;
  END IF;
END $ikke_gaeldende$;

DO $acl$
DECLARE r text; v_err text;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r,'private.membership_component_states()','EXECUTE') THEN
      RAISE EXCEPTION 'MEMBERSHIP_COMPONENT_TEST_FAILED: ACL %',r;
    END IF;
  END LOOP;
  FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
    v_err:=NULL;
    BEGIN
      EXECUTE format('SET LOCAL ROLE %I',r);
      PERFORM * FROM private.membership_component_states();
    EXCEPTION WHEN insufficient_privilege THEN v_err:=SQLERRM;
    END;
    RESET ROLE;
    IF v_err IS NULL THEN RAISE EXCEPTION 'MEMBERSHIP_COMPONENT_TEST_FAILED: % kunne kalde funktionen',r; END IF;
  END LOOP;
END $acl$;

\echo MEMBERSHIP_COMPONENT_TEST_OK
ROLLBACK;
