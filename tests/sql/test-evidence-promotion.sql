-- Isoleret sikkerhedskontrakt for evidens-promotion. Kør efter bootstrap,
-- schema.sql og db-rls.sql på en tom PostgreSQL 17-database.
--
-- Dette tester to forskellige værn separat:
--   1. direkte PostgreSQL-privilegier (ingen API-rolle kan nå private-data), og
--   2. RLS (tabellerne forbliver deny-all, også hvis en senere grant fejlagtigt
--      tilføjes).
-- Public redaktions-RPC'er er med vilje en anden kontrakt: authenticated må
-- kalde de to nye indgange, men deres interne redaktion-check afgør handlingen.

DO $evidence_promotion_rls_test$
DECLARE
  v_role text;
  v_table text;
  v_privilege text;
  v_function regprocedure;
  v_error text;
  v_state text;
  v_rls boolean;
  v_policy_count integer;
  v_public_function regprocedure;
  v_default_error text;
BEGIN
  IF to_regnamespace('private') IS NULL THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: private-schema mangler';
  END IF;

  -- Prøv den DDL-ejers aktuelle default privileges direkte. En tabel/funktion,
  -- der oprettes efter RLS-filen, må heller ikke automatisk blive API-læsbar
  -- eller -kaldbare. Proberne fjernes igen før testen eventuelt fejler.
  v_default_error:=NULL;
  BEGIN
    CREATE TABLE private._evidence_promotion_default_acl_probe (id integer);
    CREATE FUNCTION private._evidence_promotion_default_acl_probe()
      RETURNS void LANGUAGE sql AS 'SELECT NULL::void';
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
      FOREACH v_privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE'] LOOP
        IF has_table_privilege(v_role,'private._evidence_promotion_default_acl_probe',v_privilege) THEN
          RAISE EXCEPTION '% har default-% på ny private probe',v_role,v_privilege;
        END IF;
      END LOOP;
      IF has_function_privilege(v_role,
           'private._evidence_promotion_default_acl_probe()'::regprocedure,'EXECUTE') THEN
        RAISE EXCEPTION '% har default-EXECUTE på ny private probe',v_role;
      END IF;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    v_default_error:=SQLERRM;
  END;
  DROP FUNCTION IF EXISTS private._evidence_promotion_default_acl_probe();
  DROP TABLE IF EXISTS private._evidence_promotion_default_acl_probe;
  IF v_default_error IS NOT NULL THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: %',v_default_error;
  END IF;

  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: mangler rolle %', v_role;
    END IF;

    IF has_schema_privilege(v_role,'private','USAGE') THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: % har USAGE på private',v_role;
    END IF;

    FOREACH v_table IN ARRAY ARRAY[
      'private.interpretation_promotion_rule',
      'private.interpretation_promotion_batch',
      'private.interpretation_promotion',
      'private.source_record_placement_decision',
      'private.source_persona_placement_decision'
    ] LOOP
      SELECT c.relrowsecurity INTO v_rls
        FROM pg_class c WHERE c.oid=v_table::regclass;
      IF v_rls IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: RLS er ikke aktiv på %',v_table;
      END IF;
      SELECT count(*) INTO v_policy_count
        FROM pg_policy p WHERE p.polrelid=v_table::regclass;
      IF v_policy_count<>0 THEN
        RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: % har ikke deny-all-RLS',v_table;
      END IF;

      FOREACH v_privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE'] LOOP
        IF has_table_privilege(v_role,v_table,v_privilege) THEN
          RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: % har % på %',
            v_role,v_privilege,v_table;
        END IF;
      END LOOP;

      -- Den konkrete læsning beskytter mod en forkert catalog-assertion: den
      -- skal nægtes af direkte privilegier, før RLS overhovedet kan vurderes.
      v_error:=NULL; v_state:=NULL;
      BEGIN
        EXECUTE format('SET LOCAL ROLE %I',v_role);
        EXECUTE format('SELECT 1 FROM %s LIMIT 1',v_table);
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
        v_error:=SQLERRM;
      END;
      EXECUTE 'SET LOCAL ROLE NONE';
      IF v_state<>'42501' THEN
        RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: % kunne læse % (%, %)',
          v_role,v_table,v_state,v_error;
      END IF;
    END LOOP;

    FOREACH v_function IN ARRAY ARRAY[
      'private.validate_interpretation_promotion()'::regprocedure,
      'private.validate_interpretation_promotion_items(jsonb,boolean)'::regprocedure,
      'private.preview_interpretation_promotions(jsonb,boolean)'::regprocedure
    ] LOOP
      IF has_function_privilege(v_role,v_function,'EXECUTE') THEN
        RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: % kan kalde %',v_role,v_function;
      END IF;
    END LOOP;

    -- De to almindelige private validatorer skal også fejle ved reelt kald;
    -- trigger-validatoren ovenfor kan PostgreSQL kun kalde fra en trigger.
    FOREACH v_function IN ARRAY ARRAY[
      'private.validate_interpretation_promotion_items(jsonb,boolean)'::regprocedure,
      'private.preview_interpretation_promotions(jsonb,boolean)'::regprocedure
    ] LOOP
      v_error:=NULL; v_state:=NULL;
      BEGIN
        EXECUTE format('SET LOCAL ROLE %I',v_role);
        IF v_function='private.validate_interpretation_promotion_items(jsonb,boolean)'::regprocedure THEN
          PERFORM * FROM private.validate_interpretation_promotion_items('[]'::jsonb,false);
        ELSE
          PERFORM private.preview_interpretation_promotions('[]'::jsonb,false);
        END IF;
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
        v_error:=SQLERRM;
      END;
      EXECUTE 'SET LOCAL ROLE NONE';
      IF v_state<>'42501' THEN
        RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: % kunne kalde % (%, %)',
          v_role,v_function,v_state,v_error;
      END IF;
    END LOOP;
  END LOOP;

  FOREACH v_public_function IN ARRAY ARRAY[
    'public.red_promote_interpretation(uuid,text,bigint,jsonb)'::regprocedure
  ] LOOP
    IF has_function_privilege('anon',v_public_function,'EXECUTE')
       OR has_function_privilege('authenticated',v_public_function,'EXECUTE') THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: gammel promotion-RPC er eksponeret';
    END IF;
  END LOOP;

  FOREACH v_public_function IN ARRAY ARRAY[
    'public.red_preview_interpretation_promotions(jsonb)'::regprocedure,
    'public.red_promote_interpretations_batch(jsonb,text)'::regprocedure,
    'public.red_decide_source_record_placement(uuid,integer,text,jsonb)'::regprocedure,
    'public.red_decide_source_persona_placement(uuid,integer,text,jsonb)'::regprocedure
  ] LOOP
    IF has_function_privilege('anon',v_public_function,'EXECUTE')
       OR NOT has_function_privilege('authenticated',v_public_function,'EXECUTE') THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: forkert RPC-ACL for %',v_public_function;
    END IF;
  END LOOP;

  -- Authenticated har EXECUTE, men er ikke redaktion uden auth-context. Dette
  -- adskiller en gyldig funktion-grant fra redaktionsautorisering inde i RPC'en.
  v_error:=NULL; v_state:=NULL;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.red_preview_interpretation_promotions('[]'::jsonb);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
    v_error:=SQLERRM;
  END;
  SET LOCAL ROLE NONE;
  IF v_error NOT LIKE 'EVIDENCE_ROLE_FORBIDDEN%' THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: authenticated-preview gav %, %',v_state,v_error;
  END IF;

  v_error:=NULL; v_state:=NULL;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.red_promote_interpretations_batch('[]'::jsonb,'not-a-preview');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
    v_error:=SQLERRM;
  END;
  SET LOCAL ROLE NONE;
  IF v_error NOT LIKE 'EVIDENCE_ROLE_FORBIDDEN%' THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: authenticated-batch gav %, %',v_state,v_error;
  END IF;

  RAISE NOTICE 'OK: evidence promotion har deny-all private ACL/RLS og afgrænset redaktions-RPC';
END $evidence_promotion_rls_test$;
