-- Trin 6a, Task 4: afhængighedsmængden ved kildetekst-revision (text_revision_dependents), de gældende
-- bindinger over alle måltyper (text_revision_binding_set), forældelsen (supersede_for_text_revision) og det
-- reserverede grundlag i red_decide_interpretation. Alt syntetisk; én transaktion, rulles tilbage.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/person-facts.sql

-- Kopi af f2a_bound fra test-family-sources.sql.
-- Ét bundet og publiceret ægteskab i egen kilde p_base: personer p_base (hovedperson) og p_base-1 (ægtefælle).
CREATE OR REPLACE FUNCTION pg_temp.f2a_bound(p_base bigint,p_actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE s jsonb; m jsonb; pv jsonb; items jsonb;
BEGIN
  INSERT INTO person(id,levende,privat,status) VALUES (p_base,false,false,'2a'),(p_base-1,false,false,'2a');
  s:=pg_temp.f5b_source(p_base);
  m:=pg_temp.f2a_marriage(p_base,s,'B'||p_base,p_base,p_base-1,p_actor,1,1);
  PERFORM pg_temp.f2a_publish(p_base,s,m->'post',p_base,p_actor,'Anna Alfa. Gift med Bo Beta.');
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(p_base);
  PERFORM red_decide_relation_interpretations(p_base,pv->>'set_sha256');
  RESET ROLE;
  SELECT jsonb_agg(jsonb_build_object('interpretation_id',ic.id::text,'family_id',(m->>'family')::bigint)) INTO items
    FROM private.interpretation_current ic WHERE ic.interpretation_key=(m->'claim'->>'key')::uuid;
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(p_base,items);
  PERFORM red_promote_relation_interpretations_batch(p_base,items,pv->>'preview_sha256');
  RESET ROLE;
  RETURN m||jsonb_build_object('source',s);
END $$;

CREATE FUNCTION pg_temp.expect_error(p_sql text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM IS NULL OR SQLERRM NOT LIKE p_token||'%' THEN
      RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_WRONG_ERROR: expected % got %', p_token, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_NO_ERROR: expected %', p_token;
END $$;

-- Afgør den aktuelle version af en nøgle gennem redaktions-RPC'en (som authenticated redaktion).
CREATE FUNCTION pg_temp.decide(p_key uuid, p_status text, p_actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_ic record; v_new uuid;
BEGIN
  SELECT id,version INTO v_ic FROM private.interpretation_current WHERE interpretation_key=p_key;
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_new:=public.red_decide_interpretation(v_ic.id,v_ic.version,p_status,'{"basis":"t6a4 fixture"}');
  RESET ROLE;
  RETURN v_new;
END $$;

-- Ekstra link på en nøgles aktuelle version (som ejer).
CREATE FUNCTION pg_temp.link(p_key uuid, p_obs uuid, p_role text, p_ordinal int) RETURNS void LANGUAGE sql AS $$
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
  SELECT ic.id,p_obs,p_role,p_ordinal FROM private.interpretation_current ic WHERE ic.interpretation_key=p_key;
$$;

-- Nøglerne i afhængighedsmængden, sorteret.
CREATE FUNCTION pg_temp.dep_keys(p_parent uuid) RETURNS uuid[] LANGUAGE sql AS $$
  SELECT coalesce(array_agg(d.interpretation_key ORDER BY d.interpretation_key),'{}')
    FROM private.text_revision_dependents(p_parent) d
$$;

CREATE FUNCTION pg_temp.sorted(p uuid[]) RETURNS uuid[] LANGUAGE sql AS $$
  SELECT coalesce(array_agg(x ORDER BY x),'{}') FROM unnest(p) x
$$;

-- test_dependents_skip_rejected_and_superseded + test_dependents_include_unresolved
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000006a401'; s jsonb; p jsonb;
  k_prop uuid; k_rej uuid; k_sup uuid; k_acc uuid; k_unr uuid; r record; n int;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  s:=pg_temp.f5b_source(-64101);
  p:=pg_temp.f5b_post(-64101,s,'T6A4-A','Anna Alfa. Gift med Bo Beta.',ARRAY['Anna Alfa.','Gift med Bo Beta.'],NULL,v_actor);
  k_prop:=(pg_temp.f5b_claim(-64101,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift med Bo Beta.')->>'key')::uuid;
  k_rej :=(pg_temp.f5b_claim(-64101,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift med Bo Beta.')->>'key')::uuid;
  k_sup :=(pg_temp.f5b_claim(-64101,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift med Bo Beta.')->>'key')::uuid;
  k_acc :=(pg_temp.f5b_claim(-64101,s,'relation.marriage',(p->'clauses'->>0)::uuid,'Anna Alfa.')->>'key')::uuid;
  k_unr :=(pg_temp.f5b_claim(-64101,s,'relation.marriage',(p->'clauses'->>0)::uuid,'Anna Alfa.')->>'key')::uuid;
  PERFORM pg_temp.decide(k_rej,'rejected',v_actor);
  PERFORM pg_temp.decide(k_sup,'superseded',v_actor);
  PERFORM pg_temp.decide(k_acc,'accepted',v_actor);
  PERFORM pg_temp.decide(k_unr,'unresolved',v_actor);
  -- en afvist nøgle, der også linker direkte til helposten, er ikke med og udløser ingen fejl
  PERFORM pg_temp.link(k_rej,(p->>'helpost')::uuid,'context',2);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;

  IF pg_temp.dep_keys((p->>'helpost')::uuid)<>pg_temp.sorted(ARRAY[k_prop,k_acc,k_unr]) THEN
    RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: afhængighedsmængde %',pg_temp.dep_keys((p->>'helpost')::uuid);
  END IF;
  n:=0;
  FOR r IN SELECT d.*,ic.id AS ic_id,ic.status AS ic_status FROM private.text_revision_dependents((p->>'helpost')::uuid) d
             JOIN private.interpretation_current ic ON ic.interpretation_key=d.interpretation_key LOOP
    n:=n+1;
    IF r.current_id<>r.ic_id OR r.current_status<>r.ic_status THEN
      RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: aktuel række %',to_jsonb(r);
    END IF;
    IF (r.interpretation_key=k_prop AND r.current_status<>'proposed')
       OR (r.interpretation_key=k_acc AND r.current_status<>'accepted')
       OR (r.interpretation_key=k_unr AND r.current_status<>'unresolved') THEN
      RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: status %',to_jsonb(r);
    END IF;
  END LOOP;
  IF n<>3 THEN RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: % rækker',n; END IF;
  RAISE NOTICE 'OK: test_dependents_skip_rejected_and_superseded, test_dependents_include_unresolved';
END $t$;

-- test_dependents_only_current_set: en nøgle, der kun citerer det erstattede sæt 1, er ikke med.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000006a401'; s jsonb; p jsonb; k_old uuid; k_new uuid; v_c2 uuid;
BEGIN
  s:=pg_temp.f5b_source(-64102);
  p:=pg_temp.f5b_post(-64102,s,'T6A4-B','Anna Alfa. Gift med Bo Beta.',ARRAY['Anna Alfa.','Gift med Bo Beta.'],NULL,v_actor);
  -- linket skal skrives, mens sæt 1 er aktuelt
  k_old:=(pg_temp.f5b_claim(-64102,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift med Bo Beta.')->>'key')::uuid;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,
    quality_status,extraction_method,extraction_run_id,parent_observation_id,post_char_from,post_char_to,clause_ordinal,
    clause_classification,clause_flags,clause_set_seq)
  VALUES ((p->>'occ')::uuid,'clause',10,10,1000,1028,'Anna Alfa. Gift med Bo Beta.','clear','clause_segment_v1',
    (s->>'run')::uuid,(p->>'helpost')::uuid,0,28,1,'record_text','[]',2) RETURNING id INTO v_c2;
  INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence)
  SELECT o.id,1,'erstattet','machine',jsonb_build_object('manifest_sha256',repeat('a',64),'extraction_run_id',s->>'run')
    FROM private.source_observation o WHERE o.parent_observation_id=(p->>'helpost')::uuid AND o.clause_set_seq=1;
  k_new:=(pg_temp.f5b_claim(-64102,s,'relation.marriage',v_c2,'Anna Alfa. Gift med Bo Beta.')->>'key')::uuid;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.dep_keys((p->>'helpost')::uuid)<>ARRAY[k_new] THEN
    RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: kun aktuelt sæt, fik %',pg_temp.dep_keys((p->>'helpost')::uuid);
  END IF;
  RAISE NOTICE 'OK: test_dependents_only_current_set';
END $t$;

-- test_dependents_direct_helpost_link_raises
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000006a401'; s jsonb; p jsonb; p2 jsonb; k uuid;
BEGIN
  -- (a) kun et direkte link til helposten
  s:=pg_temp.f5b_source(-64103);
  p:=pg_temp.f5b_post(-64103,s,'T6A4-C','Anna Alfa. Gift med Bo Beta.',ARRAY['Anna Alfa.','Gift med Bo Beta.'],NULL,v_actor);
  PERFORM pg_temp.f5b_claim(-64103,s,'relation.marriage',(p->>'helpost')::uuid,'Anna Alfa. Gift med Bo Beta.');
  PERFORM pg_temp.expect_error(format('SELECT * FROM private.text_revision_dependents(%L)',p->>'helpost'),
    'TEXT_REVISION_DEPENDENCY_UNSUPPORTED');
  -- (b) en klausul i det aktuelle sæt og helposten selv
  p2:=pg_temp.f5b_post(-64103,s,'T6A4-D','Anna Alfa. Gift med Bo Beta.',ARRAY['Anna Alfa.','Gift med Bo Beta.'],NULL,v_actor);
  k:=(pg_temp.f5b_claim(-64103,s,'relation.marriage',(p2->'clauses'->>1)::uuid,'Gift med Bo Beta.')->>'key')::uuid;
  IF pg_temp.dep_keys((p2->>'helpost')::uuid)<>ARRAY[k] THEN RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: (b) før'; END IF;
  PERFORM pg_temp.link(k,(p2->>'helpost')::uuid,'context',2);
  PERFORM pg_temp.expect_error(format('SELECT * FROM private.text_revision_dependents(%L)',p2->>'helpost'),
    'TEXT_REVISION_DEPENDENCY_UNSUPPORTED');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  RAISE NOTICE 'OK: test_dependents_direct_helpost_link_raises';
END $t$;

-- test_dependents_cross_post_key_raises
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000006a401'; s jsonb; p1 jsonb; p2 jsonb; k uuid; v_other uuid;
BEGIN
  s:=pg_temp.f5b_source(-64104);
  p1:=pg_temp.f5b_post(-64104,s,'T6A4-E','Anna Alfa. Gift med Bo Beta.',ARRAY['Anna Alfa.','Gift med Bo Beta.'],NULL,v_actor);
  p2:=pg_temp.f5b_post(-64104,s,'T6A4-F','Cia Cecil. Gift med Dan Delta.',ARRAY['Cia Cecil.','Gift med Dan Delta.'],NULL,v_actor);
  -- (a) klausuler under to helposter: fejl fra begge sider
  k:=(pg_temp.f5b_claim(-64104,s,'relation.marriage',(p1->'clauses'->>1)::uuid,'Gift med Bo Beta.')->>'key')::uuid;
  PERFORM pg_temp.link(k,(p2->'clauses'->>1)::uuid,'context',2);
  PERFORM pg_temp.expect_error(format('SELECT * FROM private.text_revision_dependents(%L)',p1->>'helpost'),
    'TEXT_REVISION_DEPENDENCY_UNSUPPORTED');
  PERFORM pg_temp.expect_error(format('SELECT * FROM private.text_revision_dependents(%L)',p2->>'helpost'),
    'TEXT_REVISION_DEPENDENCY_UNSUPPORTED');
  -- (b) en anden observation end en klausul under helposten (her en anden posts helpost)
  s:=pg_temp.f5b_source(-64105);
  p1:=pg_temp.f5b_post(-64105,s,'T6A4-G','Anna Alfa. Gift med Bo Beta.',ARRAY['Anna Alfa.','Gift med Bo Beta.'],NULL,v_actor);
  p2:=pg_temp.f5b_post(-64105,s,'T6A4-H','Cia Cecil. Gift med Dan Delta.',ARRAY['Cia Cecil.','Gift med Dan Delta.'],NULL,v_actor);
  k:=(pg_temp.f5b_claim(-64105,s,'relation.marriage',(p1->'clauses'->>1)::uuid,'Gift med Bo Beta.')->>'key')::uuid;
  PERFORM pg_temp.link(k,(p2->>'helpost')::uuid,'context',2);
  PERFORM pg_temp.expect_error(format('SELECT * FROM private.text_revision_dependents(%L)',p1->>'helpost'),
    'TEXT_REVISION_DEPENDENCY_UNSUPPORTED');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  RAISE NOTICE 'OK: test_dependents_cross_post_key_raises';
END $t$;

-- test_binding_set_assertion_and_family: én gældende assertion-binding, én gældende familiebinding og én
-- familiebinding med forældet state_sha256 ⇒ præcis de to første.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000006a402'; a jsonb; f1 jsonb; f2 jsonb; v_pf1 uuid; v_pf2 uuid;
  v_got jsonb; v_want jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  a:=pg_temp.fpf_bound(-64201,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  f1:=pg_temp.f2a_bound(-64211,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  f2:=pg_temp.f2a_bound(-64221,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  SELECT p.id INTO v_pf1 FROM private.interpretation_promotion p JOIN private.interpretation q ON q.id=p.interpretation_id
   WHERE q.interpretation_key=(f1->'claim'->>'key')::uuid AND p.target_type='family';
  SELECT p.id INTO v_pf2 FROM private.interpretation_promotion p JOIN private.interpretation q ON q.id=p.interpretation_id
   WHERE q.interpretation_key=(f2->'claim'->>'key')::uuid AND p.target_type='family';
  IF v_pf1 IS NULL OR v_pf2 IS NULL THEN RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: familiefixture uden promotion'; END IF;
  -- gør f2's binding forældet: ordinalen indgår i relation_binding_state
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM red_set_familie_ordinal((f2->>'family')::bigint,-64221,'partner',2);
  RESET ROLE;
  PERFORM set_config('app.change_set_id','',true);
  IF private.relation_binding_state_sha256((SELECT interpretation_id FROM private.interpretation_promotion WHERE id=v_pf2))
     IS NOT DISTINCT FROM (SELECT evidence->>'state_sha256' FROM private.interpretation_promotion WHERE id=v_pf2) THEN
    RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: f2 skulle være forældet';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object('promotion_id',b.promotion_id,'target_type',b.target_type,
           'interpretation_key',b.interpretation_key,'target_id',b.target_id) ORDER BY b.target_type,b.promotion_id),'[]')
    INTO v_got
    FROM private.text_revision_binding_set(ARRAY[(a->>'interpretation_key')::uuid,(f1->'claim'->>'key')::uuid,
                                                 (f2->'claim'->>'key')::uuid]) b;
  SELECT jsonb_agg(x ORDER BY x->>'target_type',x->>'promotion_id') INTO v_want FROM (VALUES
    (jsonb_build_object('promotion_id',a->>'promotion','target_type','assertion',
       'interpretation_key',a->>'interpretation_key','target_id',a->>'assertion')),
    (jsonb_build_object('promotion_id',v_pf1,'target_type','family',
       'interpretation_key',f1->'claim'->>'key','target_id',f1->>'family'))) v(x);
  IF v_got<>v_want THEN
    RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: bindingsmængde % forventet %',v_got,v_want;
  END IF;
  -- tom/NULL input ⇒ ingen rækker, ingen fejl
  IF (SELECT count(*) FROM private.text_revision_binding_set(NULL))<>0
     OR (SELECT count(*) FROM private.text_revision_binding_set('{}'))<>0 THEN
    RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: tomt input';
  END IF;
  RAISE NOTICE 'OK: test_binding_set_assertion_and_family';
END $t$;

-- test_binding_set_unknown_target_type_raises
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000006a402'; a jsonb;
BEGIN
  a:=pg_temp.fpf_bound(-64231,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  INSERT INTO private.interpretation_promotion(interpretation_id,target_type,target_id,evidence,promoted_by,promoted_by_name)
    VALUES ((a->>'interpretation')::uuid,'fact',(a->>'fact')::bigint,'{"basis":"t6a4"}',v_actor,'fixture');
  PERFORM pg_temp.expect_error(format('SELECT * FROM private.text_revision_binding_set(ARRAY[%L]::uuid[])',a->>'interpretation_key'),
    'TEXT_REVISION_TARGET_TYPE_UNSUPPORTED');
  RAISE NOTICE 'OK: test_binding_set_unknown_target_type_raises';
END $t$;

-- test_supersede_copies_links_and_sets_basis
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000006a403'; a jsonb; s jsonb; p jsonb; k uuid; v_old uuid; v_old_a uuid;
  v_n int; r record; v_links_old jsonb; v_links_new jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  a:=pg_temp.fpf_bound(-64301,v_actor); SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF NOT private.assertion_binding_current((a->>'promotion')::uuid) THEN RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: binding før'; END IF;
  -- en nøgle med to versioner (proposed → accepted) og to links (supporting + context)
  s:=pg_temp.f5b_source(-64302);
  p:=pg_temp.f5b_post(-64302,s,'T6A4-S','Anna Alfa. Gift med Bo Beta.',ARRAY['Anna Alfa.','Gift med Bo Beta.'],NULL,v_actor);
  k:=(pg_temp.f5b_claim(-64302,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift med Bo Beta.')->>'key')::uuid;
  PERFORM pg_temp.link(k,(p->'clauses'->>0)::uuid,'context',2);
  PERFORM pg_temp.decide(k,'accepted',v_actor);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  SELECT id INTO v_old FROM private.interpretation_current WHERE interpretation_key=k;
  SELECT id INTO v_old_a FROM private.interpretation_current WHERE interpretation_key=(a->>'interpretation_key')::uuid;
  SELECT jsonb_agg(jsonb_build_array(observation_id,evidence_role,ordinal) ORDER BY ordinal) INTO v_links_old
    FROM private.interpretation_observation WHERE interpretation_id=v_old;

  -- dubletter i input forældes én gang; et forfalsket basis i p_evidence overskrives
  v_n:=private.supersede_for_text_revision(ARRAY[k,(a->>'interpretation_key')::uuid,k],v_actor,'t6a4 aktør',
    '{"basis":"forged","revision_id":"r-1","text_version_before":null,"text_version_after":"t-2"}');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF v_n<>2 THEN RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: antal %',v_n; END IF;

  FOR r IN SELECT ic.*, old.version AS old_version FROM private.interpretation_current ic
             JOIN private.interpretation old ON old.id=ic.supersedes_id
            WHERE ic.interpretation_key IN (k,(a->>'interpretation_key')::uuid) LOOP
    IF r.status<>'superseded' OR r.decision_evidence->>'basis'<>'source_text_revision'
       OR r.decision_evidence->>'revision_id'<>'r-1' OR r.decision_evidence->>'text_version_after'<>'t-2'
       OR r.version<>r.old_version+1 OR r.decided_by<>v_actor OR r.decided_by_name<>'t6a4 aktør' OR r.decided_at IS NULL
       OR r.supersedes_id NOT IN (v_old,v_old_a) THEN
      RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: ny version %',to_jsonb(r);
    END IF;
    -- samme prædikat, værdi, persona og kørsel som den aktuelle version
    IF EXISTS (SELECT 1 FROM private.interpretation old WHERE old.id=r.supersedes_id
                AND (old.predicate,old.value,old.source_persona_id,old.extraction_run_id,old.source_id)
                    IS DISTINCT FROM (r.predicate,r.value,r.source_persona_id,r.extraction_run_id,r.source_id)) THEN
      RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: kopierede felter %',to_jsonb(r);
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM private.interpretation WHERE interpretation_key=k)<>3 THEN
    RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: nøgle med to versioner skal have præcis én ny';
  END IF;
  SELECT jsonb_agg(jsonb_build_array(io.observation_id,io.evidence_role,io.ordinal) ORDER BY io.ordinal) INTO v_links_new
    FROM private.interpretation_observation io JOIN private.interpretation_current ic ON ic.id=io.interpretation_id
   WHERE ic.interpretation_key=k;
  IF v_links_new IS DISTINCT FROM v_links_old OR jsonb_array_length(v_links_new)<>2 THEN
    RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: links % forventet %',v_links_new,v_links_old;
  END IF;
  IF (SELECT count(*) FROM private.interpretation_observation io JOIN private.interpretation_current ic ON ic.id=io.interpretation_id
       WHERE ic.interpretation_key=(a->>'interpretation_key')::uuid)
     <>(SELECT count(*) FROM private.interpretation_observation WHERE interpretation_id=v_old_a) THEN
    RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: assertion-nøglens links';
  END IF;
  IF private.assertion_binding_current((a->>'promotion')::uuid) THEN
    RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: assertion_binding_current efter forældelse';
  END IF;
  -- forældede nøgler er ikke længere afhængige, og bindingsmængden er tom
  IF pg_temp.dep_keys((p->>'helpost')::uuid)<>'{}'::uuid[]
     OR (SELECT count(*) FROM private.text_revision_binding_set(ARRAY[(a->>'interpretation_key')::uuid]))<>0 THEN
    RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: efter forældelse';
  END IF;
  -- en allerede forældet eller ukendt nøgle afvises, før noget skrives
  PERFORM pg_temp.expect_error(format($q$SELECT private.supersede_for_text_revision(ARRAY[%L]::uuid[],%L,'x','{"a":1}')$q$,k,v_actor),
    'TEXT_REVISION_KEY_SET_DRIFT');
  PERFORM pg_temp.expect_error(format($q$SELECT private.supersede_for_text_revision(ARRAY[%L]::uuid[],%L,'x','{"a":1}')$q$,gen_random_uuid(),v_actor),
    'TEXT_REVISION_KEY_SET_DRIFT');
  RAISE NOTICE 'OK: test_supersede_copies_links_and_sets_basis';
END $t$;

-- test_decide_rejects_reserved_basis
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000006a404'; s jsonb; p jsonb; c jsonb; v_err text;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  s:=pg_temp.f5b_source(-64401);
  p:=pg_temp.f5b_post(-64401,s,'T6A4-R','Anna Alfa. Gift med Bo Beta.',ARRAY['Anna Alfa.','Gift med Bo Beta.'],NULL,v_actor);
  c:=pg_temp.f5b_claim(-64401,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift med Bo Beta.');
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.red_decide_interpretation((c->>'id')::uuid,1,'superseded','{"basis":"source_text_revision"}');
    v_err:='ingen fejl';
  EXCEPTION WHEN OTHERS THEN v_err:=SQLERRM;
  END;
  RESET ROLE;
  IF v_err NOT LIKE 'EVIDENCE_BASIS_RESERVED%' THEN
    RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: reserveret grundlag gav %',v_err;
  END IF;
  -- et andet grundlag virker stadig
  SET LOCAL ROLE authenticated;
  PERFORM public.red_decide_interpretation((c->>'id')::uuid,1,'accepted','{"basis":"web_detail"}');
  RESET ROLE;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  RAISE NOTICE 'OK: test_decide_rejects_reserved_basis';
END $t$;

-- De tre funktioner er private: ingen EXECUTE for PUBLIC-roller.
DO $t$
DECLARE f text; r text;
BEGIN
  FOREACH f IN ARRAY ARRAY['private.text_revision_dependents(uuid)','private.text_revision_binding_set(uuid[])',
                           'private.supersede_for_text_revision(uuid[],uuid,text,jsonb)'] LOOP
    FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      IF has_function_privilege(r,f,'EXECUTE') THEN
        RAISE EXCEPTION 'TEXT_REVISION_DEP_TEST_FAILED: % kan køre %',r,f;
      END IF;
    END LOOP;
  END LOOP;
  RAISE NOTICE 'OK: rettigheder';
END $t$;

ROLLBACK;
\echo PASS test-text-revision-dependencies
