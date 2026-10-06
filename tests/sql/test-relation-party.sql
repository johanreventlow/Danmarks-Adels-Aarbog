-- Trin 5b, Task 1: interpretation_party — parter nøglet på interpretation_key.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql

DO $relation_party_surface$
DECLARE v_role text; v_state text;
BEGIN
  IF to_regclass('private.interpretation_party') IS NULL OR to_regclass('private.interpretation_party_current') IS NULL THEN
    RAISE EXCEPTION 'RELATION_PARTY_TEST_FAILED: tabel eller view mangler';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private.interpretation_party'::regclass) THEN
    RAISE EXCEPTION 'RELATION_PARTY_TEST_FAILED: RLS er slået fra';
  END IF;
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    v_state:=NULL;
    BEGIN
      EXECUTE format('SET LOCAL ROLE %I',v_role);
      PERFORM 1 FROM private.interpretation_party LIMIT 1;
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
    END;
    EXECUTE 'SET LOCAL ROLE NONE';
    IF v_state IS DISTINCT FROM '42501' THEN
      RAISE EXCEPTION 'RELATION_PARTY_TEST_FAILED: % kunne læse (%)',v_role,v_state;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: interpretation_party har RLS og ingen API-adgang';
END $relation_party_surface$;

DO $relation_party_rules$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-00000005b101';
  s jsonb; p1 jsonb; p2 jsonb; c jsonb; c_child jsonb; v_spouse uuid; v_other uuid; v_err text; v_new uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-5101,false,false,'5b'),(-5102,false,false,'5b');
  s:=pg_temp.f5b_source(-5101);
  p1:=pg_temp.f5b_post(-5101,s,'I-1','Anna Alfa, f. 1800. g. m. Bo Beta, f. 1801.',
       ARRAY['Anna Alfa, f. 1800.','g. m. Bo Beta, f. 1801.'],-5101,v_actor);
  p2:=pg_temp.f5b_post(-5101,s,'I-2','Carl Alfa, f. 1830. søn af Anna Alfa.',
       ARRAY['Carl Alfa, f. 1830.','søn af Anna Alfa.'],-5102,v_actor);
  c:=pg_temp.f5b_claim(-5101,s,'relation.marriage',(p1->'clauses'->>1)::uuid,'g. m. Bo Beta, f. 1801.');
  c_child:=pg_temp.f5b_claim(-5101,s,'relation.parent',(p2->'clauses'->>1)::uuid,'søn af Anna Alfa.');
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES (-5101,'I-1#spouse',(s->>'run')::uuid)
    RETURNING id INTO v_spouse;
  -- spouse-mention i ægteskabsklausulen, så scope-triggeren passerer og CHECK'en (ordinal) er det, der afviser
  INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
    VALUES ((p1->'clauses'->>1)::uuid,'person',6,13,'Bo Beta',(s->>'run')::uuid) RETURNING id INTO v_other;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_spouse,v_other,'spouse',1);

  -- principal fra samme post: godkendt (version 1)
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((c->>'key')::uuid,'principal',1,(p1->>'principal')::uuid,20,'relation_persona',gen_random_uuid());
  -- forkert version afvises
  BEGIN
    INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
      VALUES ((c->>'key')::uuid,'principal',3,(p1->>'principal')::uuid,20,'relation_persona',gen_random_uuid());
    RAISE EXCEPTION 'RELATION_PARTY_TEST_FAILED: versionsspring godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'EVIDENCE_PARTY_VERSION_CONFLICT%' THEN RAISE; END IF;
  END;
  -- child-rolle på et ægteskab afvises
  BEGIN
    INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
      VALUES ((c->>'key')::uuid,'child',1,(p2->>'principal')::uuid,NULL,'relation_decision',gen_random_uuid());
    RAISE EXCEPTION 'RELATION_PARTY_TEST_FAILED: child på ægteskab godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'EVIDENCE_PARTY_ROLE_INVALID%' THEN RAISE; END IF;
  END;
  -- principal fra en anden post afvises
  BEGIN
    INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
      VALUES ((c->>'key')::uuid,'principal',2,(p2->>'principal')::uuid,20,'relation_persona',gen_random_uuid());
    RAISE EXCEPTION 'RELATION_PARTY_TEST_FAILED: fremmed principal godtaget';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'EVIDENCE_PARTY_SCOPE_INVALID%' THEN RAISE; END IF;
  END;
  -- parent fra en anden post (dennes hovedperson) godkendt
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((c_child->>'key')::uuid,'principal',1,(p2->>'principal')::uuid,20,'relation_persona',gen_random_uuid());
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,origin,origin_ref)
    VALUES ((c_child->>'key')::uuid,'parent',1,(p1->>'principal')::uuid,'relation_decision',gen_random_uuid());
  -- spouse uden ordinal afvises
  BEGIN
    INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
      VALUES ((c->>'key')::uuid,'spouse',1,v_spouse,20,'relation_persona',gen_random_uuid());
    RAISE EXCEPTION 'RELATION_PARTY_TEST_FAILED: spouse uden ordinal godtaget';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  -- append-only
  BEGIN
    UPDATE private.interpretation_party SET post_offset=0 WHERE interpretation_key=(c->>'key')::uuid;
    RAISE EXCEPTION 'RELATION_PARTY_TEST_FAILED: UPDATE lykkedes';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'EVIDENCE_APPEND_ONLY:%' THEN RAISE; END IF;
  END;
  -- parterne følger fortolkningen gennem en ny version (nøglet på interpretation_key)
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_new:=red_decide_interpretation((c->>'id')::uuid,1,'unresolved','{"note":"5b party-test"}'::jsonb);
  RESET ROLE;
  IF (SELECT count(*) FROM private.interpretation_party_current pc
       JOIN private.interpretation_current ic ON ic.interpretation_key=pc.interpretation_key
      WHERE ic.id=v_new)<>1 THEN
    RAISE EXCEPTION 'RELATION_PARTY_TEST_FAILED: parterne fulgte ikke den nye version';
  END IF;
  RAISE NOTICE 'OK: roller, version, rolleafhængigt post-scope, append-only og versionsoverlevelse';
END $relation_party_rules$;
ROLLBACK;
