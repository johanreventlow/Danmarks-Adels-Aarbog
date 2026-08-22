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
  IF to_regprocedure('private.prelock_identity_relation_update(jsonb,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'IDENTITY_UPDATE_PRELOCK_HELPER_MISSING';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid = 'private.prelock_identity_relation_update(jsonb,jsonb)'::regprocedure
      AND p.prosecdef
      AND 'search_path=pg_catalog, public, private' = ANY (p.proconfig)
  ) OR has_function_privilege('anon','private.prelock_identity_relation_update(jsonb,jsonb)','EXECUTE')
       OR has_function_privilege('authenticated','private.prelock_identity_relation_update(jsonb,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'IDENTITY_UPDATE_PRELOCK_HELPER_SECURITY_DRIFT';
  END IF;
  v_definition := pg_get_functiondef('private.prelock_identity_relation_update(jsonb,jsonb)'::regprocedure);
  v_lock_position := strpos(v_definition, 'pg_advisory_xact_lock(hashtext(''samme_som_mutation''))');
  v_people_position := strpos(v_definition, 'private.lock_identity_people');
  IF v_lock_position < 1 OR v_people_position <= v_lock_position THEN
    RAISE EXCEPTION 'IDENTITY_UPDATE_PRELOCK_ORDER_DRIFT';
  END IF;
  IF v_definition ~ 'app\.identity_relation_update_prelock' THEN
    RAISE EXCEPTION 'IDENTITY_UPDATE_PRELOCK_WRITABLE_MARKER_DRIFT';
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
  IF regexp_count(v_definition, 'private\.lock_identity_people') <> 1
     OR v_definition !~ 'IDENTITY_RELATION_UPDATE_PRELOCK_REQUIRED'
     OR v_definition !~ 'pg_catalog\.pg_locks'
     OR v_definition !~ 'v_advisory_key >> 32'
     OR v_definition !~ '4294967295'
     OR v_definition !~ 'pg_catalog\.pg_advisory_unlock'
     OR v_definition !~ 'pg_catalog\.pg_try_advisory_xact_lock'
     OR v_definition !~ 'pg_catalog\.pg_try_advisory_lock'
     OR v_definition !~ 'client_min_messages'
     OR v_definition !~ 'IDENTITY_PERSON_NOT_FOUND'
     OR v_definition !~ 'public\.person'
     OR v_definition ~ 'app\.identity_relation_update_prelock' THEN
    RAISE EXCEPTION 'IDENTITY_TRIGGER_LOCK_HELPER_DRIFT';
  END IF;
  v_definition := pg_get_functiondef('public._version_upsert_row(text,jsonb)'::regprocedure);
  IF strpos(v_definition,'private.prelock_identity_relation_update') < 1
     OR strpos(v_definition,'private.prelock_identity_relation_update') > strpos(v_definition,'UPDATE %1$I SET') THEN
    RAISE EXCEPTION 'IDENTITY_VERSION_UPSERT_PRELOCK_DRIFT';
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
  v_raw_relation bigint := -1939501098;
  v_change_sets_before bigint; v_change_sets_after bigint; v_same bigint;
  v_current jsonb; v_target jsonb;
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

  -- A caller-writable custom GUC is not proof that advisory/person locks were acquired.
  INSERT INTO public.relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
  VALUES (v_raw_relation,'person',p_low,'person',p_high,'bekendt_med');
  SELECT to_jsonb(r) || jsonb_build_object('rolle','ikke_samme_som')
    INTO v_target FROM public.relation r WHERE r.id=v_raw_relation;
  PERFORM set_config(
    'app.identity_relation_update_prelock',
    jsonb_build_array(
      v_target->'id',v_target->'rolle',v_target->'subjekt_type',v_target->'subjekt_id',
      v_target->'objekt_type',v_target->'objekt_id'
    )::text,
    true
  );
  BEGIN
    UPDATE public.relation SET rolle='ikke_samme_som' WHERE id=v_raw_relation;
    RAISE EXCEPTION 'EXPECTED_SPOOFED_IDENTITY_PRELOCK_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'IDENTITY_RELATION_UPDATE_PRELOCK_REQUIRED' THEN RAISE; END IF;
  END;
  PERFORM set_config('app.identity_relation_update_prelock','',true);
  PERFORM public._version_upsert_row(
    'relation',
    (SELECT to_jsonb(r) || jsonb_build_object('periode_raw','generic undo remains supported')
     FROM public.relation r WHERE r.id=v_raw_relation)
  );
  IF (SELECT periode_raw FROM public.relation WHERE id=v_raw_relation)
     <> 'generic undo remains supported' THEN
    RAISE EXCEPTION 'GENERIC_NON_IDENTITY_VERSION_UPSERT_REGRESSED';
  END IF;
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
  SELECT to_jsonb(r) INTO v_current FROM public.relation r WHERE r.id=v_update_rejection;
  v_target := v_current || jsonb_build_object('subjekt_id',w1,'objekt_id',wc);
  BEGIN
    PERFORM private.prelock_identity_relation_update(v_current,v_target);
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

-- A caught component contradiction rolls back its subtransaction advisory lock.  A retry
-- must not inherit authorization from the old writable marker, while the correctly pre-held
-- lock must reach the normal Task 1 contradiction check.
BEGIN;
DELETE FROM public.relation WHERE id IN (-1939501199,-1939501198,-1939501197);
DELETE FROM public.person WHERE id IN (-1939501101,-1939501102,-1939501103,-1939501104);
DELETE FROM public.profiles WHERE id='19390000-0000-4000-8000-000000000005';
DELETE FROM auth.users WHERE id='19390000-0000-4000-8000-000000000005';
COMMIT;

BEGIN;
DO $setup_reusable_proof$
DECLARE
  v_actor uuid := '19390000-0000-4000-8000-000000000005';
BEGIN
  INSERT INTO auth.users(id,email) VALUES(v_actor,'c3-identity-prelock@test.invalid')
    ON CONFLICT (id) DO UPDATE SET email=excluded.email;
  INSERT INTO public.profiles(id,email,rolle,navn)
    VALUES(v_actor,'c3-identity-prelock@test.invalid','redaktion','C3 identity prelock test')
    ON CONFLICT (id) DO UPDATE
      SET email=excluded.email,rolle=excluded.rolle,navn=excluded.navn;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  INSERT INTO public.person(id,levende,koen) VALUES
    (-1939501101,false,'ukendt'),(-1939501102,false,'ukendt'),
    (-1939501103,false,'ukendt'),(-1939501104,false,'ukendt')
    ON CONFLICT (id) DO UPDATE SET levende=excluded.levende,koen=excluded.koen;
  INSERT INTO public.relation(id,subjekt_type,subjekt_id,rolle,objekt_type,objekt_id) VALUES
    (-1939501199,'person',-1939501103,'bekendt_med','person',-1939501104),
    (-1939501198,'person',-1939501101,'samme_som','person',-1939501102),
    (-1939501197,'person',-1939501103,'ikke_samme_som','person',-1939501104);
END $setup_reusable_proof$;
COMMIT;

BEGIN;
DO $reusable_proof$
DECLARE
  v_actor uuid := '19390000-0000-4000-8000-000000000005';
  v_current jsonb; v_target jsonb; v_has_lock boolean;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SELECT to_jsonb(r) INTO v_current FROM public.relation r WHERE r.id=-1939501197;
  v_target := v_current || jsonb_build_object('subjekt_id',-1939501101,'objekt_id',-1939501102);

  -- pg_locks shows the same identity for session and transaction locks. Session-only proof
  -- must nevertheless fail closed, and the test must restore/release its own lock on error.
  BEGIN
    PERFORM pg_advisory_lock(hashtext('samme_som_mutation'));
    BEGIN
      UPDATE public.relation
        SET subjekt_id=-1939501101,objekt_id=-1939501102
        WHERE id=-1939501197;
      RAISE EXCEPTION 'EXPECTED_SESSION_ONLY_PRELOCK_REJECTION';
    EXCEPTION WHEN others THEN
      IF SQLERRM <> 'IDENTITY_RELATION_UPDATE_PRELOCK_REQUIRED' THEN RAISE; END IF;
    END;
    IF NOT pg_advisory_unlock(hashtext('samme_som_mutation')) THEN
      RAISE EXCEPTION 'IDENTITY_SESSION_LOCK_CLEANUP_FAILED';
    END IF;
  EXCEPTION WHEN others THEN
    PERFORM pg_advisory_unlock(hashtext('samme_som_mutation'));
    RAISE;
  END;
  SELECT EXISTS (
    SELECT 1 FROM pg_catalog.pg_locks l
    WHERE l.locktype='advisory' AND l.pid=pg_backend_pid() AND l.granted
      AND l.classid=(CASE WHEN hashtext('samme_som_mutation') < 0
                          THEN 4294967295::bigint ELSE 0::bigint END)::oid
      AND l.objid=(hashtext('samme_som_mutation')::bigint & 4294967295::bigint)::oid
      AND l.objsubid=1
  ) INTO v_has_lock;
  IF v_has_lock THEN RAISE EXCEPTION 'IDENTITY_SESSION_SCOPE_PROBE_LOCK_LEAKED'; END IF;

  BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('different_identity_mutation'));
    UPDATE public.relation SET rolle='ikke_samme_som' WHERE id=-1939501199;
    RAISE EXCEPTION 'EXPECTED_DIFFERENT_ADVISORY_KEY_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'IDENTITY_RELATION_UPDATE_PRELOCK_REQUIRED' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
    UPDATE public.relation SET objekt_id=-1939501196 WHERE id=-1939501197;
    RAISE EXCEPTION 'EXPECTED_PREHELD_LOCK_PERSON_NOT_FOUND';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'IDENTITY_PERSON_NOT_FOUND' THEN RAISE; END IF;
  END;

  PERFORM set_config('app.identity_relation_update_prelock','',true);
  BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
    UPDATE public.relation
      SET subjekt_id=-1939501101,objekt_id=-1939501102
      WHERE id=-1939501197;
    RAISE EXCEPTION 'EXPECTED_PREHELD_LOCK_COMPONENT_CONTRADICTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%IDENTITY_COMPONENT_CONTRADICTION%' THEN RAISE; END IF;
  END;
  PERFORM set_config(
    'app.identity_relation_update_prelock',
    jsonb_build_array(
      v_target->'id',v_target->'rolle',v_target->'subjekt_type',v_target->'subjekt_id',
      v_target->'objekt_type',v_target->'objekt_id'
    )::text,
    true
  );
  BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
    UPDATE public.relation
      SET subjekt_id=-1939501101,objekt_id=-1939501102
      WHERE id=-1939501197;
    RAISE EXCEPTION 'EXPECTED_REUSABLE_PROOF_COMPONENT_CONTRADICTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%IDENTITY_COMPONENT_CONTRADICTION%' THEN RAISE; END IF;
  END;
  SELECT EXISTS (
    SELECT 1 FROM pg_catalog.pg_locks l
    WHERE l.locktype='advisory' AND l.pid=pg_backend_pid() AND l.granted
      AND l.mode='ExclusiveLock'
      AND l.classid=(CASE WHEN hashtext('samme_som_mutation') < 0
                          THEN 4294967295::bigint ELSE 0::bigint END)::oid
      AND l.objid=(hashtext('samme_som_mutation')::bigint & 4294967295::bigint)::oid
      AND l.objsubid=1
  ) INTO v_has_lock;
  IF v_has_lock THEN RAISE EXCEPTION 'IDENTITY_SUBTRANSACTION_ADVISORY_LOCK_LEAKED'; END IF;
  BEGIN
    UPDATE public.relation
      SET subjekt_id=-1939501101,objekt_id=-1939501102
      WHERE id=-1939501197;
    RAISE EXCEPTION 'EXPECTED_REUSED_IDENTITY_PRELOCK_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'IDENTITY_RELATION_UPDATE_PRELOCK_REQUIRED' THEN RAISE; END IF;
  END;
END $reusable_proof$;
ROLLBACK;

BEGIN;
DELETE FROM public.relation WHERE id IN (-1939501199,-1939501198,-1939501197);
DELETE FROM public.person WHERE id IN (-1939501101,-1939501102,-1939501103,-1939501104);
DELETE FROM public.profiles WHERE id='19390000-0000-4000-8000-000000000005';
DELETE FROM auth.users WHERE id='19390000-0000-4000-8000-000000000005';
COMMIT;
