\set ON_ERROR_STOP on

BEGIN;

DO $catalog$
DECLARE
  v_definition text;
  v_lock_position integer;
  v_people_position integer;
  v_writer regprocedure;
BEGIN
  IF to_regprocedure('private.lock_identity_people(bigint[])') IS NULL THEN
    RAISE EXCEPTION 'IDENTITY_LOCK_HELPER_MISSING';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid = 'private.lock_identity_people(bigint[])'::regprocedure
      AND p.prosecdef
      AND 'search_path=pg_catalog, public, private' = ANY (p.proconfig)
  ) THEN
    RAISE EXCEPTION 'IDENTITY_LOCK_HELPER_SECURITY_DRIFT';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f',p.proowner))) acl
    WHERE p.oid = 'private.lock_identity_people(bigint[])'::regprocedure
      AND acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
  )
     OR has_function_privilege('anon','private.lock_identity_people(bigint[])','EXECUTE')
     OR has_function_privilege('authenticated','private.lock_identity_people(bigint[])','EXECUTE') THEN
    RAISE EXCEPTION 'IDENTITY_LOCK_HELPER_ACL_DRIFT';
  END IF;

  v_definition := pg_get_functiondef('private.lock_identity_people(bigint[])'::regprocedure);
  IF v_definition !~ 'SELECT DISTINCT x FROM unnest\(p_person_ids\) x WHERE x IS NOT NULL'
     OR v_definition !~ 'ORDER BY p.id FOR UPDATE' THEN
    RAISE EXCEPTION 'IDENTITY_LOCK_HELPER_SORT_DEDUP_DRIFT';
  END IF;

  FOREACH v_writer IN ARRAY ARRAY[
    'public.red_samme_som(bigint,bigint)'::regprocedure,
    'public.red_ikke_samme_som(bigint,bigint)'::regprocedure,
    'public.red_slet_person(bigint)'::regprocedure
  ] LOOP
    v_definition := pg_get_functiondef(v_writer);
    v_lock_position := strpos(v_definition, 'pg_advisory_xact_lock(hashtext(''samme_som_mutation''))');
    v_people_position := strpos(v_definition, 'private.lock_identity_people');
    IF v_lock_position < 1 OR v_people_position <= v_lock_position THEN
      RAISE EXCEPTION 'IDENTITY_WRITER_LOCK_ORDER_DRIFT: %', v_writer;
    END IF;
  END LOOP;
  v_definition := pg_get_functiondef('public.enforce_samme_som_invariants()'::regprocedure);
  IF regexp_count(v_definition, 'private\.lock_identity_people') <> 2 THEN
    RAISE EXCEPTION 'IDENTITY_TRIGGER_LOCK_HELPER_DRIFT';
  END IF;
END $catalog$;

DO $test$
DECLARE
  v_actor uuid := '19390000-0000-4000-8000-000000000001';
  a1 bigint := -1939501001; a2 bigint := -1939501002; ac bigint := -1939501003;
  b1 bigint := -1939501004; b2 bigint := -1939501005; bc bigint := -1939501006;
  c1 bigint := -1939501007; c2 bigint := -1939501008;
  u1 bigint := -1939501009; uc bigint := -1939501010; v1 bigint := -1939501011;
  w1 bigint := -1939501012; w2 bigint := -1939501013; wc bigint := -1939501014;
  x1 bigint := -1939501015; x2 bigint := -1939501016;
  p_low bigint := -1939501017; p_high bigint := -1939501018; p_missing bigint := -1939501099;
  v_rejection bigint; v_remove_change_set bigint; v_update_rejection bigint;
  v_change_sets_before bigint; v_change_sets_after bigint; v_same bigint;
BEGIN
  INSERT INTO auth.users(id,email)
  VALUES (v_actor,'c3-identity-invariants@test.invalid')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.profiles(id,email,rolle,navn)
  VALUES (v_actor,'c3-identity-invariants@test.invalid','redaktion','C3 identity invariant test')
  ON CONFLICT (id) DO UPDATE SET rolle='redaktion', navn='C3 identity invariant test';
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  IF public.current_rolle() <> 'redaktion' THEN
    RAISE EXCEPTION 'IDENTITY_INVARIANT_TEST_ACTOR_NOT_REDAKTION';
  END IF;

  INSERT INTO public.person(id,levende,koen) VALUES
    (a1,false,'mand'), (a2,false,'mand'), (ac,false,'mand'),
    (b1,false,'kvinde'), (b2,false,'kvinde'), (bc,false,'kvinde'),
    (c1,false,'ukendt'), (c2,false,'ukendt'),
    (u1,false,'mand'), (uc,false,'mand'), (v1,false,'kvinde'),
    (w1,false,'mand'), (w2,false,'kvinde'), (wc,false,'mand'),
    (x1,false,'ukendt'), (x2,false,'ukendt'),
    (p_low,false,'ukendt'), (p_high,false,'ukendt')
  ON CONFLICT (id) DO NOTHING;

  -- Negative bigint fixture IDs are valid; NULLs and duplicates do not inflate the expected set.
  PERFORM private.lock_identity_people(ARRAY[p_high,p_low,p_low,NULL]);
  BEGIN
    PERFORM private.lock_identity_people(ARRAY[p_low,p_missing,NULL]);
    RAISE EXCEPTION 'EXPECTED_IDENTITY_PERSON_NOT_FOUND';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'IDENTITY_PERSON_NOT_FOUND' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM private.lock_identity_people(ARRAY[NULL]::bigint[]);
    RAISE EXCEPTION 'EXPECTED_IDENTITY_EMPTY_PERSON_SET_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'IDENTITY_PERSON_NOT_FOUND' THEN RAISE; END IF;
  END;

  -- Task 1 made raw INSERT/UPDATE restoration paths authoritative too; they must share the
  -- same endpoint existence check rather than merely taking locks on whichever rows survive.
  BEGIN
    INSERT INTO public.relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM public.relation),
            'person',p_low,'person',p_missing,'samme_som');
    RAISE EXCEPTION 'EXPECTED_RAW_SAME_PERSON_NOT_FOUND';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'IDENTITY_PERSON_NOT_FOUND' THEN RAISE; END IF;
  END;
  BEGIN
    INSERT INTO public.relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM public.relation),
            'person',p_low,'person',p_missing,'ikke_samme_som');
    RAISE EXCEPTION 'EXPECTED_RAW_DIFFERENT_PERSON_NOT_FOUND';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'IDENTITY_PERSON_NOT_FOUND' THEN RAISE; END IF;
  END;

  -- A rejection between separate components succeeds and remains idempotent.
  v_rejection := public.red_ikke_samme_som(c1,c2);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  SELECT count(*) INTO v_change_sets_before FROM public.change_set;
  IF public.red_ikke_samme_som(c2,c1) <> v_rejection THEN
    RAISE EXCEPTION 'IDENTITY_SEPARATE_REJECTION_IDEMPOTENCY_FAILED';
  END IF;
  SELECT count(*) INTO v_change_sets_after FROM public.change_set;
  IF v_change_sets_after <> v_change_sets_before
     OR coalesce(current_setting('app.change_set_id',true),'') <> '' THEN
    RAISE EXCEPTION 'IDENTITY_REJECTION_IDEMPOTENCY_CREATED_EMPTY_CHANGE_SET';
  END IF;

  -- Same-as idempotency also remains before begin_change_set after locking.
  v_same := public.red_samme_som(x1,x2);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  SELECT count(*) INTO v_change_sets_before FROM public.change_set;
  IF public.red_samme_som(x1,x2) <> v_same THEN
    RAISE EXCEPTION 'IDENTITY_SAME_IDEMPOTENCY_FAILED';
  END IF;
  SELECT count(*) INTO v_change_sets_after FROM public.change_set;
  IF v_change_sets_after <> v_change_sets_before
     OR coalesce(current_setting('app.change_set_id',true),'') <> '' THEN
    RAISE EXCEPTION 'IDENTITY_SAME_IDEMPOTENCY_CREATED_EMPTY_CHANGE_SET';
  END IF;

  -- Component A: a1 -> ac and a2 -> ac.  Its members cannot be rejected.
  PERFORM public.red_samme_som(a1,ac);
  PERFORM public.red_samme_som(a2,ac);
  -- The trigger layer must also reject a raw/version-restore insert, not only the RPC.
  BEGIN
    INSERT INTO public.relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM public.relation),
            'person',a1,'person',a2,'ikke_samme_som');
    RAISE EXCEPTION 'EXPECTED_TRIGGER_COMPONENT_DIFFERENT_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%IDENTITY_COMPONENT_CONTRADICTION%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.red_ikke_samme_som(a1,a2);
    RAISE EXCEPTION 'EXPECTED_COMPONENT_DIFFERENT_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%IDENTITY_COMPONENT_CONTRADICTION%' THEN RAISE; END IF;
  END;

  -- Component B is separate.  Its existing rejection must block every bridge edge.
  PERFORM public.red_samme_som(b1,bc);
  PERFORM public.red_samme_som(b2,bc);
  PERFORM public.red_ikke_samme_som(a1,b1);
  BEGIN
    PERFORM public.red_samme_som(a2,b2);
    RAISE EXCEPTION 'EXPECTED_COMPONENT_SAME_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%IDENTITY_COMPONENT_CONTRADICTION%' THEN RAISE; END IF;
  END;

  -- An existing rejection cannot be UPDATEd into one same-as component.
  v_update_rejection := public.red_ikke_samme_som(w1,w2);
  PERFORM public.red_samme_som(w1,wc);
  BEGIN
    UPDATE public.relation SET subjekt_id=w1, objekt_id=wc WHERE id=v_update_rejection;
    RAISE EXCEPTION 'EXPECTED_TRIGGER_COMPONENT_UPDATE_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%IDENTITY_COMPONENT_CONTRADICTION%' THEN RAISE; END IF;
  END;

  -- Normal undo restores the deleted rejection through _version_upsert_row and must fail closed.
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  PERFORM public.red_samme_som(u1,uc);
  v_rejection := public.red_ikke_samme_som(u1,v1);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  PERFORM public.red_fjern_ikke_samme_som(v_rejection);
  v_remove_change_set := current_setting('app.change_set_id',true)::bigint;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  -- Reuse the deleted relation ID with another rejection, forcing undo onto UPDATE rather than INSERT.
  PERFORM public.red_ikke_samme_som(p_low,p_high);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  PERFORM public.red_samme_som(v1,uc);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  BEGIN
    PERFORM public.red_fortryd_change_set(v_remove_change_set,true);
    RAISE EXCEPTION 'EXPECTED_UNDO_COMPONENT_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%IDENTITY_COMPONENT_CONTRADICTION%' THEN RAISE; END IF;
  END;

  -- The private SECURITY DEFINER helper must not become an owner-only identity oracle.
  PERFORM set_config('request.jwt.claim.sub','19390000-0000-4000-8000-000000000099',true);
  BEGIN
    PERFORM private.identity_components_have_rejection(c1,c2);
    RAISE EXCEPTION 'EXPECTED_IDENTITY_COMPONENT_HELPER_ROLE_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%Kun redaktion%' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM private.lock_identity_people(ARRAY[c1,c2]);
    RAISE EXCEPTION 'EXPECTED_IDENTITY_LOCK_HELPER_ROLE_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%Kun redaktion%' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'OK: C3 identity contradictions, sorted person locks, and direct idempotency';
END $test$;

ROLLBACK;
