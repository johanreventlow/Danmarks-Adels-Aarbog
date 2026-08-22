\set ON_ERROR_STOP on

BEGIN;

DO $test$
DECLARE
  v_actor uuid := '19390000-0000-4000-8000-000000000001';
  a1 bigint := -1939501001; a2 bigint := -1939501002; ac bigint := -1939501003;
  b1 bigint := -1939501004; b2 bigint := -1939501005; bc bigint := -1939501006;
  c1 bigint := -1939501007; c2 bigint := -1939501008;
  v_rejection bigint;
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
    (c1,false,'ukendt'), (c2,false,'ukendt')
  ON CONFLICT (id) DO NOTHING;

  -- A rejection between separate components succeeds and remains idempotent.
  v_rejection := public.red_ikke_samme_som(c1,c2);
  IF public.red_ikke_samme_som(c2,c1) <> v_rejection THEN
    RAISE EXCEPTION 'IDENTITY_SEPARATE_REJECTION_IDEMPOTENCY_FAILED';
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

  -- The private SECURITY DEFINER helper must not become an owner-only identity oracle.
  PERFORM set_config('request.jwt.claim.sub','19390000-0000-4000-8000-000000000099',true);
  BEGIN
    PERFORM private.identity_components_have_rejection(c1,c2);
    RAISE EXCEPTION 'EXPECTED_IDENTITY_COMPONENT_HELPER_ROLE_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%Kun redaktion%' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'OK: C3 component-wide identity contradictions and direct idempotency';
END $test$;

ROLLBACK;
