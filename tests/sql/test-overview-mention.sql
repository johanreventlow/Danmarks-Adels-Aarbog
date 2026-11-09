-- Trin 6d-2a: oversigtsreglen (private.overview_mention_narratives) og biografilæseren. Opdigtede personer, kilder og
-- linjer (negative id'er). Kontrakt v1 (CI-standard): publiceringsgaten er narrativets privat-flag + offentlig person,
-- og narrativer uden binding er legacy-rækker i biografilæseren.
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

-- Reglens rækker for de givne personer som '<person>:<narrativ>:<kilde>:<detalje>', sorteret.
CREATE OR REPLACE FUNCTION pg_temp.ov(p_ids bigint[]) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce(string_agg(r.person_id||':'||r.narrative_id||':'||r.source_id||':'||r.detail_person_id,',' ORDER BY r.narrative_id),'')
    FROM private.overview_mention_narratives(p_ids) r
$$;
CREATE OR REPLACE FUNCTION pg_temp.ov_expect(p_name text,p_ids bigint[],p_expected text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v text:=pg_temp.ov(p_ids);
BEGIN
  IF v IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION 'OVERVIEW_MENTION_TEST_FAILED: % forventet [%] fik [%]',p_name,p_expected,v;
  END IF;
END $$;

DO $grundtilfaelde$
DECLARE f jsonb:=pg_temp.f6d_src(-6101); nq bigint; np bigint;
BEGIN
  nq:=pg_temp.ov_member(f,'I-1',-610101,1);
  np:=pg_temp.ov_mention(-610102,-6101);
  PERFORM pg_temp.ov_expect('grundtilfaelde uden kant',ARRAY[-610101,-610102],'');
  PERFORM pg_temp.f6d_same(-610102,-610101,'afklaret');
  PERFORM pg_temp.ov_expect('grundtilfaelde',ARRAY[-610101,-610102],'-610102:'||np||':-6101:-610101');
  -- retningen er uden betydning
  DELETE FROM public.conclusion WHERE target_type='relation' AND target_id IN (SELECT id FROM public.relation WHERE rolle='samme_som' AND subjekt_id IN (-610101,-610102));
  DELETE FROM public.relation WHERE rolle='samme_som' AND subjekt_id IN (-610101,-610102);
  PERFORM pg_temp.f6d_same(-610101,-610102,'afklaret');
  PERFORM pg_temp.ov_expect('grundtilfaelde omvendt retning',ARRAY[-610101,-610102],'-610102:'||np||':-6101:-610101');
END $grundtilfaelde$;

DO $selv_medlem$
DECLARE f jsonb:=pg_temp.f6d_src(-6111);
BEGIN
  PERFORM pg_temp.ov_member(f,'I-1',-611101,1);
  PERFORM pg_temp.ov_member(f,'I-2',-611102,2);
  PERFORM pg_temp.f6d_same(-611102,-611101,'afklaret');
  PERFORM pg_temp.ov_expect('selv_medlem',ARRAY[-611101,-611102],'');
END $selv_medlem$;

DO $q_ikke_offentlig$
DECLARE f jsonb:=pg_temp.f6d_src(-6121);
BEGIN
  PERFORM pg_temp.ov_member(f,'I-1',-612101,1);
  PERFORM pg_temp.ov_mention(-612102,-6121);
  PERFORM pg_temp.f6d_same(-612102,-612101,'afklaret');
  UPDATE public.person SET levende=true WHERE id=-612101;
  PERFORM pg_temp.ov_expect('q levende',ARRAY[-612102],'');
  UPDATE public.person SET levende=false,privat=true WHERE id=-612101;
  PERFORM pg_temp.ov_expect('q privat',ARRAY[-612102],'');
  UPDATE public.person SET privat=false,staged=true WHERE id=-612101;
  PERFORM pg_temp.ov_expect('q staged',ARRAY[-612102],'');
  UPDATE public.person SET staged=false WHERE id=-612101;
  IF pg_temp.ov(ARRAY[-612102])='' THEN RAISE EXCEPTION 'OVERVIEW_MENTION_TEST_FAILED: q_ikke_offentlig kontrol'; END IF;
END $q_ikke_offentlig$;

DO $q_uden_tekst$
DECLARE f jsonb:=pg_temp.f6d_src(-6131);
BEGIN
  PERFORM pg_temp.ov_member(f,'I-1',-613101,1,false);
  PERFORM pg_temp.ov_mention(-613102,-6131);
  PERFORM pg_temp.f6d_same(-613102,-613101,'afklaret');
  PERFORM pg_temp.ov_expect('q uden tekst',ARRAY[-613102],'');
END $q_uden_tekst$;

DO $anden_kilde$
DECLARE f1 jsonb:=pg_temp.f6d_src(-6141); f2 jsonb;
BEGIN
  f2:=pg_temp.f6d_src(-6142,(f1->>'lineage')::bigint);
  PERFORM pg_temp.ov_member(f2,'I-1',-614101,1);          -- Q er medlem og har tekst kun i kilde -6142
  PERFORM pg_temp.ov_mention(-614102,-6141);               -- P har tekst i kilde -6141
  PERFORM pg_temp.f6d_same(-614102,-614101,'afklaret');
  PERFORM pg_temp.ov_expect('anden kilde',ARRAY[-614102],'');
END $anden_kilde$;

DO $ikke_afklaret$
DECLARE f jsonb:=pg_temp.f6d_src(-6151); np bigint;
BEGIN
  PERFORM pg_temp.ov_member(f,'I-1',-615101,1);
  np:=pg_temp.ov_mention(-615102,-6151);
  PERFORM pg_temp.f6d_same(-615102,-615101,'omstridt');
  PERFORM pg_temp.ov_expect('omstridt',ARRAY[-615102],'');
END $ikke_afklaret$;

DO $konklusion_senere$
DECLARE f jsonb:=pg_temp.f6d_src(-6161); np bigint; v_rel bigint;
BEGIN
  PERFORM pg_temp.ov_member(f,'I-1',-616101,1);
  np:=pg_temp.ov_mention(-616102,-6161);
  v_rel:=pg_temp.f6d_same(-616102,-616101,NULL);
  PERFORM pg_temp.ov_expect('uden konklusion',ARRAY[-616102],'');
  INSERT INTO public.conclusion(target_type,target_id,status) VALUES ('relation',v_rel,'afklaret');
  PERFORM pg_temp.ov_expect('konklusion senere',ARRAY[-616102],'-616102:'||np||':-6161:-616101');
END $konklusion_senere$;

DO $kant_fjernet$
DECLARE f jsonb:=pg_temp.f6d_src(-6171); np bigint; v_rel bigint;
BEGIN
  PERFORM pg_temp.ov_member(f,'I-1',-617101,1);
  np:=pg_temp.ov_mention(-617102,-6171);
  v_rel:=pg_temp.f6d_same(-617102,-617101,'afklaret');
  PERFORM pg_temp.ov_expect('kant sat',ARRAY[-617102],'-617102:'||np||':-6171:-617101');
  DELETE FROM public.conclusion WHERE target_type='relation' AND target_id=v_rel;
  DELETE FROM public.relation WHERE id=v_rel;
  PERFORM pg_temp.ov_expect('kant fjernet',ARRAY[-617102],'');
END $kant_fjernet$;

DO $medlemskab_ugaeldende$
DECLARE f jsonb:=pg_temp.f6d_src(-6181); v_persona uuid; np bigint;
BEGIN
  v_persona:=pg_temp.f6d_place(f,'I-1',-618101,1);
  PERFORM pg_temp.f6d_promote(f);
  INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,tekst) VALUES ('person',-618101,-6181,'q');
  np:=pg_temp.ov_mention(-618102,-6181);
  PERFORM pg_temp.f6d_same(-618102,-618101,'afklaret');
  PERFORM pg_temp.ov_expect('før omafgørelse',ARRAY[-618102],'-618102:'||np||':-6181:-618101');
  INSERT INTO public.person(id) VALUES (-618199);
  UPDATE private.source_persona_identity SET canonical_person_id=-618199,version=2 WHERE source_persona_id=v_persona;
  PERFORM pg_temp.ov_expect('medlemskab ugyldigt',ARRAY[-618102],'');
END $medlemskab_ugaeldende$;

DO $placement_ugaeldende$
DECLARE f jsonb:=pg_temp.f6d_src(-6191); v_persona uuid; np bigint; v_pp uuid;
BEGIN
  v_persona:=pg_temp.f6d_place(f,'I-1',-619101,1);
  PERFORM pg_temp.f6d_promote(f);
  INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,tekst) VALUES ('person',-619101,-6191,'q');
  np:=pg_temp.ov_mention(-619102,-6191);
  PERFORM pg_temp.f6d_same(-619102,-619101,'afklaret');
  PERFORM pg_temp.ov_expect('før afvisning',ARRAY[-619102],'-619102:'||np||':-6191:-619101');
  SELECT id INTO v_pp FROM private.source_persona_placement WHERE source_persona_id=v_persona;
  INSERT INTO private.source_persona_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by,decided_by_name)
    VALUES (v_pp,2,'superseded','{"rule":"test"}','redaction',(f->>'actor')::uuid,'test');
  IF private.membership_is_current(-619101,(f->>'lineage')::bigint) THEN
    RAISE EXCEPTION 'OVERVIEW_MENTION_TEST_FAILED: medlemskabet stadig gældende efter afvisning';
  END IF;
  PERFORM pg_temp.ov_expect('placement ugyldig',ARRAY[-619102],'');
END $placement_ugaeldende$;

DO $q_tekst_trukket$
DECLARE f jsonb:=pg_temp.f6d_src(-6201); nq bigint; np bigint;
BEGIN
  nq:=pg_temp.ov_member(f,'I-1',-620101,1);
  np:=pg_temp.ov_mention(-620102,-6201);
  PERFORM pg_temp.f6d_same(-620102,-620101,'afklaret');
  PERFORM pg_temp.ov_expect('før tilbagetrækning',ARRAY[-620102],'-620102:'||np||':-6201:-620101');
  UPDATE public.narrative SET privat=true WHERE id=nq;   -- kontrakt v1: publiceringsgaten er privat-flaget
  IF public.person_daa_narrative_publication_allowed(nq) THEN RAISE EXCEPTION 'OVERVIEW_MENTION_TEST_FAILED: opsætning trukket'; END IF;
  PERFORM pg_temp.ov_expect('q tekst trukket',ARRAY[-620102],'');
END $q_tekst_trukket$;

DO $skjult_mellemled$
DECLARE f jsonb:=pg_temp.f6d_src(-6211); np bigint;
BEGIN
  PERFORM pg_temp.ov_member(f,'I-1',-621101,1);
  np:=pg_temp.ov_mention(-621102,-6211);
  INSERT INTO public.person(id,levende) VALUES (-621103,true);              -- R: ikke offentlig
  PERFORM pg_temp.f6d_same(-621102,-621103,'afklaret');
  PERFORM pg_temp.f6d_same(-621101,-621103,'afklaret');
  PERFORM pg_temp.ov_expect('skjult mellemled',ARRAY[-621102],'');
  UPDATE public.person SET levende=false WHERE id=-621103;
  PERFORM pg_temp.ov_expect('offentligt mellemled',ARRAY[-621102],'-621102:'||np||':-6211:-621101');
END $skjult_mellemled$;

DO $kun_forespurgte$
DECLARE f jsonb:=pg_temp.f6d_src(-6221); np bigint;
BEGIN
  PERFORM pg_temp.ov_member(f,'I-1',-622101,1);
  np:=pg_temp.ov_mention(-622102,-6221);
  PERFORM pg_temp.f6d_same(-622102,-622101,'afklaret');
  PERFORM pg_temp.ov_expect('kun Q forespurgt',ARRAY[-622101],'');
  PERFORM pg_temp.ov_expect('kun P forespurgt',ARRAY[-622102],'-622102:'||np||':-6221:-622101');
  PERFORM pg_temp.ov_expect('tom liste',ARRAY[]::bigint[],'');
  IF (SELECT count(*) FROM private.overview_mention_narratives(NULL))<>0 THEN
    RAISE EXCEPTION 'OVERVIEW_MENTION_TEST_FAILED: NULL-liste';
  END IF;
END $kun_forespurgte$;

DO $mindste_q$
DECLARE f jsonb:=pg_temp.f6d_src(-6231); np bigint;
BEGIN
  PERFORM pg_temp.ov_member(f,'I-1',-623105,1);
  PERFORM pg_temp.ov_member(f,'I-2',-623103,2);
  np:=pg_temp.ov_mention(-623102,-6231);
  PERFORM pg_temp.f6d_same(-623105,-623102,'afklaret');
  PERFORM pg_temp.f6d_same(-623103,-623102,'afklaret');
  PERFORM pg_temp.ov_expect('mindste Q',ARRAY[-623102],'-623102:'||np||':-6231:-623105');
END $mindste_q$;

DO $acl$
DECLARE r text; v_err text;
BEGIN
  IF to_regprocedure('private.overview_mention_narratives(bigint[])') IS NULL THEN
    RAISE EXCEPTION 'OVERVIEW_MENTION_TEST_FAILED: funktionen mangler';
  END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r,'private.overview_mention_narratives(bigint[])','EXECUTE') THEN
      RAISE EXCEPTION 'OVERVIEW_MENTION_TEST_FAILED: ACL %',r;
    END IF;
  END LOOP;
  FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
    v_err:=NULL;
    BEGIN
      EXECUTE format('SET LOCAL ROLE %I',r);
      PERFORM * FROM private.overview_mention_narratives(ARRAY[1]::bigint[]);
    EXCEPTION WHEN insufficient_privilege THEN v_err:=SQLERRM;
    END;
    RESET ROLE;
    IF v_err IS NULL THEN RAISE EXCEPTION 'OVERVIEW_MENTION_TEST_FAILED: % kunne kalde funktionen',r; END IF;
  END LOOP;
END $acl$;

\echo OVERVIEW_MENTION_TEST_OK
ROLLBACK;
