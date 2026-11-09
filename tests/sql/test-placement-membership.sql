-- #150 trin 5c-1 (spec 2026-10-26 §4.4): membership via promotion fra accepteret persona-placement, gyldig kun ved
-- passende tilstands-sha, med preview, reversal og vagter.
\set ON_ERROR_STOP on

BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/placement-150.sql

-- Kilde med én placeret hovedperson (accepteret record- og persona-placement) og en ægtefælle-persona i samme post.
CREATE OR REPLACE FUNCTION pg_temp.f150_placed(p_source bigint,p_person bigint) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE f jsonb:=pg_temp.f150_source(p_source); p jsonb; v_obs uuid; v_rp uuid; v_pp uuid; v_sp uuid; v_mention uuid;
BEGIN
  p:=pg_temp.f150_post(f,'I-1',p_person,1,1);
  PERFORM private.write_header_evidence(p_source,(f->>'rend')::uuid,pg_temp.f150_run(),
    jsonb_build_array(pg_temp.f150_h('header_linje',500,'I DEN TESTSKE LINJE')));
  v_obs:=private.header_observation_uuid((f->>'rend')::uuid,'header-2018-20-v1',500);
  v_rp:=private.write_record_placement((p->>'record')::uuid,(f->>'entry')::bigint,'{"printed_number":"1"}',v_obs,
    jsonb_build_object('rule_version','header-2018-20-v1','header_ids',jsonb_build_object('linje',v_obs)));
  v_pp:=private.write_persona_placement((p->>'principal')::uuid,v_rp,(p->>'helpost')::uuid,'{"rule":"test"}');
  -- Ægtefælle: egen persona på samme helpost-mention, accepteret til en anden person, med en accepteret
  -- mentioned_spouse-placement. Den må aldrig få et item.
  SELECT mention_id INTO v_mention FROM private.source_persona_mention WHERE persona_id=(p->>'principal')::uuid;
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES (p_source,'I-1-spouse',(f->>'run')::uuid)
    RETURNING id INTO v_sp;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_sp,v_mention,'spouse',1);
  INSERT INTO public.person(id) VALUES (p_person-50);
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at) VALUES (v_sp,p_person-50,'accepted',1,'{"fixture":"150"}',(f->>'actor')::uuid,'fixture',now());
  INSERT INTO private.source_persona_placement(source_persona_id,record_placement_id,placement_role,basis_observation_id,initial_status)
    VALUES (v_sp,v_rp,'mentioned_spouse',(p->>'helpost')::uuid,'accepted') RETURNING id INTO v_sp;
  INSERT INTO private.source_persona_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
    VALUES (v_sp,1,'accepted','{"fixture":"150"}','migration','fixture');
  RETURN f||jsonb_build_object('post',p,'rp',v_rp,'pp',v_pp);
END $$;

DO $promotion$
DECLARE f jsonb:=pg_temp.f150_placed(-1531,-153101); v jsonb; v_n int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  SET LOCAL ROLE authenticated;
  v:=public.red_preview_placement_memberships(-1531);
  IF jsonb_array_length(v->'items')<>1 OR (v#>>'{items,0,person_id}')::bigint<>-153101
     OR NOT (v#>>'{items,0,eligible}')::boolean OR (v#>>'{items,0,lineage_id}')::bigint<>(f->>'lineage')::bigint THEN
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: preview %',v;
  END IF;
  v_n:=public.red_promote_placement_memberships(-1531,v->>'preview_sha256');
  RESET ROLE;
  IF v_n<>1 OR btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: promote n=% eller GUC ikke ryddet',v_n;
  END IF;
  IF (SELECT role FROM public.person_lineage_membership WHERE person_id=-153101)<>'member'
     OR (SELECT membership_kind FROM public.person_slaegt_membership WHERE person_id=-153101)<>'agnatic'
     OR NOT private.membership_is_current(-153101,(f->>'lineage')::bigint)
     OR EXISTS (SELECT 1 FROM public.person_slaegt_membership WHERE person_id=-153151) THEN
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: membership-rækker';
  END IF;
  IF (SELECT source_basis->>'state_sha256' FROM public.person_lineage_membership WHERE person_id=-153101)
       IS DISTINCT FROM private.reimport_canonical_json_sha256(private.membership_state((f->>'pp')::uuid)) THEN
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: source_basis bærer ikke tilstands-sha';
  END IF;
  -- Genkørsel: intet nyt at fremme.
  SET LOCAL ROLE authenticated;
  v:=public.red_preview_placement_memberships(-1531);
  IF (v#>>'{items,0,reason_code}')<>'already_current' OR public.red_promote_placement_memberships(-1531,v->>'preview_sha256')<>0 THEN
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: genkørsel %',v;
  END IF;
  RESET ROLE;
  -- Reversal sletter begge rækker under et change_set (før-billedet bevares i change_event).
  SET LOCAL ROLE authenticated;
  PERFORM public.red_reverse_placement_membership(-153101,(f->>'lineage')::bigint,'test');
  RESET ROLE;
  IF EXISTS (SELECT 1 FROM public.person_lineage_membership WHERE person_id=-153101)
     OR EXISTS (SELECT 1 FROM public.person_slaegt_membership WHERE person_id=-153101)
     OR (SELECT count(*) FROM public.change_event WHERE op='DELETE' AND row_pk->>'person_id'='-153101'
           AND tabel IN ('person_lineage_membership','person_slaegt_membership'))<>2 THEN
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: reversal';
  END IF;
END $promotion$;

DO $membership_forael$
DECLARE f jsonb:=pg_temp.f150_placed(-1532,-153201); v jsonb; v_notice text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  SET LOCAL ROLE authenticated;
  v:=public.red_preview_placement_memberships(-1532);
  PERFORM public.red_promote_placement_memberships(-1532,v->>'preview_sha256');
  RESET ROLE;
  IF private.placement_membership_not_current()<>0 THEN
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: frisk membership talt som ikke-gældende';
  END IF;
  -- Identiteten afgøres igen til en anden person: membershippen bliver ikke-gældende og tælles.
  INSERT INTO public.person(id) VALUES (-153299);
  UPDATE private.source_persona_identity SET canonical_person_id=-153299,version=2
   WHERE source_persona_id=(f#>>'{post,principal}')::uuid;
  IF private.membership_is_current(-153201,(f->>'lineage')::bigint) OR private.placement_membership_not_current()<>1 THEN
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: forældet membership stadig gældende';
  END IF;
END $membership_forael$;

DO $vagter$
DECLARE f jsonb:=pg_temp.f150_placed(-1533,-153301); v jsonb; v_err text;
BEGIN
  -- Uden redaktion-rolle.
  BEGIN
    PERFORM set_config('request.jwt.claim.sub','a1500000-0000-0000-0000-00000000ffff',true);
    SET LOCAL ROLE authenticated;
    PERFORM public.red_preview_placement_memberships(-1533);
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: preview uden rolle';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'EVIDENCE_ROLE_FORBIDDEN%' THEN RAISE; END IF;
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  SET LOCAL ROLE authenticated;
  v:=public.red_preview_placement_memberships(-1533);
  -- Anden preview-sha → drift.
  BEGIN
    PERFORM public.red_promote_placement_memberships(-1533,repeat('0',64));
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: forkert preview-sha godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'PLACEMENT_MEMBERSHIP_PREVIEW_DRIFT%' THEN RAISE; END IF;
  END;
  -- Fremmed aktivt change_set.
  BEGIN
    PERFORM set_config('app.change_set_id','987654',true);
    PERFORM public.red_promote_placement_memberships(-1533,v->>'preview_sha256');
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: fremmed change_set godtaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'PLACEMENT_MEMBERSHIP_FOREIGN_CHANGE_SET%' THEN RAISE; END IF;
  END;
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  -- En membership i samme kilde, som en anden placement ejer → konflikt, intet skrives. (En anden kildes række er
  -- PLACEMENT_MEMBERSHIP_FOREIGN_SOURCE; se $fremmed_kilde$.)
  INSERT INTO public.person_lineage_membership(person_id,lineage_id,role,source_basis)
    VALUES (-153301,(f->>'lineage')::bigint,'member','{"basis":"redaktør","source_id":-1533}');
  SET LOCAL ROLE authenticated;
  v:=public.red_preview_placement_memberships(-1533);
  IF (v#>>'{items,0,reason_code}')<>'conflict' THEN RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: konflikt ikke vist'; END IF;
  BEGIN
    PERFORM public.red_promote_placement_memberships(-1533,v->>'preview_sha256');
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: konflikt fremmet';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'PLACEMENT_MEMBERSHIP_CONFLICT%' THEN RAISE; END IF;
  END;
  RESET ROLE;
  IF EXISTS (SELECT 1 FROM public.person_slaegt_membership WHERE person_id=-153301) THEN
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: konflikt skrev slægtsmedlemskab';
  END IF;
END $vagter$;

-- Trin 6d-1 (Codex r1 #4, #6): promotionen rører aldrig en anden kildes membership-række. Forhåndstjek før det
-- generelle konfliktstop, og atomisk i selve upserten.
DO $fremmed_kilde$
DECLARE f jsonb:=pg_temp.f150_placed(-1534,-153401); v jsonb; v_err text; v_before jsonb;
BEGIN
  INSERT INTO public.person_lineage_membership(person_id,lineage_id,role,source_basis)
    VALUES (-153401,(f->>'lineage')::bigint,'member','{"basis":"2018-20","source_id":1}');
  SELECT source_basis INTO v_before FROM public.person_lineage_membership WHERE person_id=-153401;
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  SET LOCAL ROLE authenticated;
  v:=public.red_preview_placement_memberships(-1534);
  BEGIN
    PERFORM public.red_promote_placement_memberships(-1534,v->>'preview_sha256');
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: en anden kildes linjemedlemskab overskrevet';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'PLACEMENT_MEMBERSHIP_FOREIGN_SOURCE%' THEN RAISE; END IF;
  END;
  RESET ROLE;
  IF (SELECT source_basis FROM public.person_lineage_membership WHERE person_id=-153401) IS DISTINCT FROM v_before
     OR (SELECT count(*) FROM public.person_lineage_membership WHERE person_id=-153401)<>1
     OR EXISTS (SELECT 1 FROM public.person_slaegt_membership WHERE person_id=-153401) THEN
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: fremmed kilde ændrede rækker';
  END IF;
  -- Også en anden kildes slægtsmedlemskab alene stopper promotionen.
  DELETE FROM public.person_lineage_membership WHERE person_id=-153401;
  INSERT INTO public.person_slaegt_membership(person_id,slaegt_id,membership_kind,source_basis)
    VALUES (-153401,(f->>'slaegt')::bigint,'agnatic','{"basis":"2018-20","source_id":1}');
  SET LOCAL ROLE authenticated;
  v:=public.red_preview_placement_memberships(-1534);
  BEGIN
    PERFORM public.red_promote_placement_memberships(-1534,v->>'preview_sha256');
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: en anden kildes slægtsmedlemskab overskrevet';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'PLACEMENT_MEMBERSHIP_FOREIGN_SOURCE%' THEN RAISE; END IF;
  END;
  RESET ROLE;
  IF EXISTS (SELECT 1 FROM public.person_lineage_membership WHERE person_id=-153401)
     OR (SELECT source_basis->>'source_id' FROM public.person_slaegt_membership WHERE person_id=-153401)<>'1' THEN
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: fremmed slægtskilde ændrede rækker';
  END IF;
END $fremmed_kilde$;

DO $fremmed_kilde_null$
DECLARE f jsonb:=pg_temp.f150_placed(-1535,-153501); v jsonb; v_err text;
BEGIN
  -- En række uden source_id (fx redaktørskrevet) er ikke kildens egen.
  INSERT INTO public.person_lineage_membership(person_id,lineage_id,role,source_basis)
    VALUES (-153501,(f->>'lineage')::bigint,'founder','{"basis":"redaktør"}');
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  SET LOCAL ROLE authenticated;
  v:=public.red_preview_placement_memberships(-1535);
  BEGIN
    PERFORM public.red_promote_placement_memberships(-1535,v->>'preview_sha256');
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: række uden kilde overskrevet';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'PLACEMENT_MEMBERSHIP_FOREIGN_SOURCE%' THEN RAISE; END IF;
  END;
  RESET ROLE;
  IF (SELECT role||'/'||source_basis::text FROM public.person_lineage_membership WHERE person_id=-153501)
       <>'founder/{"basis": "redaktør"}'
     OR EXISTS (SELECT 1 FROM public.person_slaegt_membership WHERE person_id=-153501) THEN
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: række uden kilde ændret';
  END IF;
END $fremmed_kilde_null$;

-- En anden kildes slægtsrække, der opstår mellem forhåndstjekket og skrivningen (simuleret af en midlertidig trigger
-- på linjetabellen), må ikke overskrives: slægts-upserten rammer 0 rækker → FOREIGN_SOURCE, alt rulles tilbage.
CREATE OR REPLACE FUNCTION pg_temp.f6d_samtidig_fremmed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.person_id=-153601 THEN
    INSERT INTO public.person_slaegt_membership(person_id,slaegt_id,membership_kind,source_basis)
      VALUES (NEW.person_id,(NEW.source_basis->>'slaegt_id')::bigint,'agnatic','{"basis":"samtidig","source_id":1}');
  END IF;
  RETURN NULL;
END $$;

DO $fremmed_kilde_i_skrivning$
DECLARE f jsonb:=pg_temp.f150_placed(-1536,-153601); v jsonb; v_err text;
BEGIN
  CREATE TRIGGER trg_f6d_samtidig_fremmed AFTER INSERT ON public.person_lineage_membership
    FOR EACH ROW EXECUTE FUNCTION pg_temp.f6d_samtidig_fremmed();
  PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
  SET LOCAL ROLE authenticated;
  v:=public.red_preview_placement_memberships(-1536);
  IF NOT (v#>>'{items,0,eligible}')::boolean THEN RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: ikke egnet %',v; END IF;
  BEGIN
    PERFORM public.red_promote_placement_memberships(-1536,v->>'preview_sha256');
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: samtidig fremmed slægtsrække overskrevet';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'PLACEMENT_MEMBERSHIP_FOREIGN_SOURCE%' THEN RAISE; END IF;
  END;
  RESET ROLE;
  DROP TRIGGER trg_f6d_samtidig_fremmed ON public.person_lineage_membership;
  IF EXISTS (SELECT 1 FROM public.person_lineage_membership WHERE person_id=-153601)
     OR EXISTS (SELECT 1 FROM public.person_slaegt_membership WHERE person_id=-153601)
     OR btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: skrivningen blev ikke rullet tilbage';
  END IF;
END $fremmed_kilde_i_skrivning$;

DO $acl$
BEGIN
  IF has_function_privilege('anon','public.red_preview_placement_memberships(bigint)','EXECUTE')
     OR has_function_privilege('anon','public.red_promote_placement_memberships(bigint,text)','EXECUTE')
     OR has_function_privilege('anon','public.red_reverse_placement_membership(bigint,bigint,text)','EXECUTE')
     -- Supabase's DEFAULT PRIVILEGES giver service_role EXECUTE på nye funktioner i prod; RPC'erne skal fratage den.
     OR has_function_privilege('service_role','public.red_preview_placement_memberships(bigint)','EXECUTE')
     OR has_function_privilege('service_role','public.red_promote_placement_memberships(bigint,text)','EXECUTE')
     OR has_function_privilege('service_role','public.red_reverse_placement_membership(bigint,bigint,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_promote_placement_memberships(bigint,text)','EXECUTE')
     OR has_function_privilege('authenticated','private.membership_state(uuid)','EXECUTE')
     OR has_function_privilege('authenticated','private.membership_is_current(bigint,bigint)','EXECUTE') THEN
    RAISE EXCEPTION 'PLACEMENT_MEMBERSHIP_TEST_FAILED: ACL';
  END IF;
END $acl$;

\echo PLACEMENT_MEMBERSHIP_TEST_OK
ROLLBACK;
