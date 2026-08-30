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
  IF NOT EXISTS (
    SELECT 1
      FROM pg_catalog.pg_extension e
      JOIN pg_catalog.pg_namespace n ON n.oid=e.extnamespace
     WHERE e.extname='pgcrypto' AND n.nspname='extensions'
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: pgcrypto ligger ikke i extensions';
  END IF;
  IF EXISTS (
    SELECT 1
      FROM pg_catalog.pg_namespace n,
           LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) acl
     WHERE n.nspname='extensions'
       AND acl.grantee=0
       AND acl.privilege_type='CREATE'
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: PUBLIC har CREATE på extensions';
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
    IF has_schema_privilege(v_role,'extensions','CREATE') THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: % har CREATE på extensions',v_role;
    END IF;

    FOREACH v_table IN ARRAY ARRAY[
      'private.interpretation_promotion_rule',
      'private.interpretation_promotion_rule_line',
      'private.interpretation_promotion_authorization',
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
      'private.preview_interpretation_promotions(jsonb,boolean)'::regprocedure,
      'private.canonical_interpretation_promotion_items(jsonb)'::regprocedure,
      'private.interpretation_promotion_profile(jsonb)'::regprocedure,
      'private.validate_interpretation_promotion_profile(jsonb)'::regprocedure,
      'private.interpretation_promotion_database_identity()'::regprocedure,
      'private.interpretation_promotion_batch_state(uuid)'::regprocedure,
      'private.guard_interpretation_promotion_authorization_mutation()'::regprocedure,
      'private.guard_interpretation_promotion_batch_mutation()'::regprocedure,
      'private.add_interpretation_promotion_rule_version(text,text,text,text,text,text,boolean,boolean,boolean,text)'::regprocedure
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

  IF to_regprocedure('public.red_promote_interpretations_batch(jsonb,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: legacy batch-overload findes stadig';
  END IF;
  IF to_regprocedure('public.red_promote_interpretation(uuid,text,bigint,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: legacy single-row writer findes stadig';
  END IF;

  FOREACH v_public_function IN ARRAY ARRAY[
    'public.red_preview_interpretation_promotions(jsonb)'::regprocedure,
    'public.red_authorize_interpretation_promotions(jsonb,text,uuid,timestamptz)'::regprocedure,
    'public.red_promote_interpretations_batch(jsonb,text,uuid)'::regprocedure,
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
    PERFORM public.red_authorize_interpretation_promotions(
      '[]'::jsonb,'not-a-preview','91000000-0000-0000-0000-000000000099',clock_timestamp()+interval '1 minute'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
    v_error:=SQLERRM;
  END;
  SET LOCAL ROLE NONE;
  IF v_error NOT LIKE 'EVIDENCE_ROLE_FORBIDDEN%' THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_RLS_TEST_FAILED: authenticated-authorize gav %, %',v_state,v_error;
  END IF;

  RAISE NOTICE 'OK: evidence promotion har deny-all private ACL/RLS og afgrænset redaktions-RPC';
END $evidence_promotion_rls_test$;

DO $evidence_promotion_canonical_scope_test$
DECLARE
  v_forward jsonb:=jsonb_build_array(
    jsonb_build_object('interpretation_id','c1000000-0000-0000-0000-000000000002','target_type','assertion','target_id',2),
    jsonb_build_object('interpretation_id','c1000000-0000-0000-0000-000000000001','target_type','assertion','target_id',1)
  );
  v_reverse jsonb;
  v_error text;
BEGIN
  v_reverse:=jsonb_build_array(v_forward->1,v_forward->0);
  IF private.canonical_interpretation_promotion_items(v_forward)
       IS DISTINCT FROM private.canonical_interpretation_promotion_items(v_reverse) THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_CANONICAL_SCOPE_FAILED: item order changed scope';
  END IF;
  v_error:=NULL;
  BEGIN
    INSERT INTO private.interpretation_promotion_batch(
      rule_profile_hash,preview_hash,promoted_by,promoted_by_name,requested_count,status
    ) VALUES (repeat('0',64),repeat('1',64),gen_random_uuid(),'bypass',1,'legacy_quarantined');
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  IF v_error IS NULL THEN
    RAISE EXCEPTION 'EVIDENCE_PROMOTION_CANONICAL_SCOPE_FAILED: new legacy batch bypass succeeded';
  END IF;
  RAISE NOTICE 'OK: promotion request scope is canonical across item ordering';
END $evidence_promotion_canonical_scope_test$;

-- En gyldig, kildebunden promotion skal gennem begge SHA-256-stier med
-- Supabases faktiske pgcrypto-layout. Hele fixturen rulles tilbage, så testen
-- også kan køres mod en database med eksisterende data.
DO $evidence_promotion_digest_success_test$
DECLARE
  v_actor uuid := '11000000-0000-0000-0000-000000000091';
  v_other_actor uuid := '11000000-0000-0000-0000-000000000092';
  v_run uuid := '22000000-0000-0000-0000-000000000091';
  v_rendition uuid := '33000000-0000-0000-0000-000000000091';
  v_occurrence uuid := '55000000-0000-0000-0000-000000000091';
  v_observation uuid := '66000000-0000-0000-0000-000000000091';
  v_mention uuid := '70000000-0000-0000-0000-000000000091';
  v_persona uuid := '88000000-0000-0000-0000-000000000091';
  v_interpretation uuid := 'c1000000-0000-0000-0000-000000000091';
  v_accepted uuid;
  v_preview jsonb;
  v_items jsonb;
  v_authorization uuid;
  v_receipt jsonb;
  v_error text;
  v_before integer;
  v_current jsonb;
BEGIN
  BEGIN
    INSERT INTO auth.users(id,email)
      VALUES (v_actor,'promotion-digest-success@test.invalid');
    INSERT INTO auth.users(id,email)
      VALUES (v_other_actor,'promotion-digest-other@test.invalid');
    INSERT INTO profiles(id,rolle,navn,email)
      VALUES (v_actor,'redaktion','Promotion Digest Success',
              'promotion-digest-success@test.invalid');
    INSERT INTO profiles(id,rolle,navn,email)
      VALUES (v_other_actor,'redaktion','Promotion Digest Other',
              'promotion-digest-other@test.invalid');
    INSERT INTO person(id,levende,privat,status)
      VALUES (-987650091,false,false,'promotion digest fixture');
    INSERT INTO source(id,titel,import_key)
      VALUES (-987650091,'Promotion digest success','verify:promotion:digest');
    INSERT INTO private.extraction_run(
      id,source_id,run_key,schema_version,extractor_version,profile_version,
      input_sha256,manifest
    ) VALUES (
      v_run,-987650091,'promotion-digest-run','1.0','verify','verify',repeat('9',64),'{}'
    );
    INSERT INTO private.source_rendition(
      id,source_id,rendition_key,rendition_kind,content_sha256,metadata
    ) VALUES (
      v_rendition,-987650091,'promotion-digest-rendition','text_layer',repeat('8',64),'{}'
    );
    INSERT INTO private.source_record_occurrence(
      id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
      verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id
    ) VALUES (
      v_occurrence,v_rendition,'promotion-digest-occurrence',1,1,0,11,
      'Anna Digest','physical-promotion-digest','structural-promotion-digest',v_run
    );
    INSERT INTO private.source_observation(
      id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
      verbatim_text,quality_status,extraction_method,extraction_run_id
    ) VALUES (
      v_observation,v_occurrence,'name_clause',1,1,0,11,'Anna Digest',
      'clear','verify',v_run
    );
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
      VALUES (v_persona,-987650091,'promotion-digest-persona',v_run);
    INSERT INTO private.source_mention(
      id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id
    ) VALUES (v_mention,v_observation,'person',0,11,'Anna Digest',v_run);
    INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
      VALUES (v_persona,v_mention,'principal',1);
    INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype)
      VALUES (-987650091,'person',-987650091,'navn');
    INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,calendar,uforanderlig)
      VALUES (-987650091,'fact',-987650091,'Anna Digest','gregoriansk',true);
    INSERT INTO private.interpretation(
      id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
      predicate,value,schema_version,derivation_kind,confidence,status,method,
      extraction_run_id
    ) VALUES (
      v_interpretation,'c0000000-0000-0000-0000-000000000091',1,-987650091,
      v_persona,'property','person.name','"Anna Digest"','1.0','source_statement',
      1,'proposed','verify',v_run
    );
    INSERT INTO private.interpretation_observation(
      interpretation_id,observation_id,evidence_role,ordinal
    ) VALUES (v_interpretation,v_observation,'supporting',1);
    SET CONSTRAINTS private.interpretation_has_observation IMMEDIATE;
    SET CONSTRAINTS private.interpretation_has_observation DEFERRED;

    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    SET LOCAL ROLE authenticated;
    PERFORM red_decide_source_persona_identity(
      v_persona,-987650091,0,'accepted','{"basis":"digest success regression"}'
    );
    SELECT red_decide_interpretation(
      v_interpretation,1,'accepted','{"basis":"digest success regression"}'
    ) INTO v_accepted;
    v_items:=jsonb_build_array(jsonb_build_object(
      'interpretation_id',v_accepted,'target_type','assertion','target_id',-987650091
    ));
    v_preview:=red_preview_interpretation_promotions(v_items);
    IF v_preview->'items'->0->>'eligible'<>'true'
       OR v_preview->>'preview_hash' !~ '^[0-9a-f]{64}$' THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_DIGEST_TEST_FAILED: ugyldigt preview %',v_preview;
    END IF;
    v_authorization:=red_authorize_interpretation_promotions(
      v_items,v_preview->>'preview_hash',
      '91000000-0000-0000-0000-000000000091',clock_timestamp()+interval '5 minutes'
    );
    v_error:=NULL;
    BEGIN
      PERFORM red_authorize_interpretation_promotions(v_items,v_preview->>'preview_hash',
        '91000000-0000-0000-0000-000000000093',clock_timestamp()+interval '5 minutes');
    EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
    END;
    IF v_error IS NULL OR v_error NOT LIKE 'EVIDENCE_PROMOTION_SCOPE_ALREADY_AUTHORIZED%' THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_DIGEST_TEST_FAILED: duplicate scope guard missing: %',v_error;
    END IF;
    RESET ROLE;
    SELECT count(*) INTO v_before FROM private.interpretation_promotion_batch;
    SET LOCAL ROLE authenticated;
    v_error:=NULL;
    BEGIN
      PERFORM red_authorize_interpretation_promotions(
        v_items || jsonb_build_array(jsonb_build_object('interpretation_id',gen_random_uuid(),'target_type','assertion','target_id',-987650091)),
        v_preview->>'preview_hash','91000000-0000-0000-0000-000000000094',clock_timestamp()+interval '5 minutes');
    EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
    END;
    RESET ROLE;
    IF v_error IS NULL OR (SELECT count(*) FROM private.interpretation_promotion_batch)<>v_before THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_DIGEST_TEST_FAILED: mixed invalid request was not atomic: %',v_error;
    END IF;
    SET session_replication_role=replica;
    UPDATE private.interpretation_promotion_authorization SET rule_profile='{"unknown":true}'::jsonb WHERE id=v_authorization;
    SET session_replication_role=origin;
    SET LOCAL ROLE authenticated;
    v_error:=NULL;
    BEGIN PERFORM red_promote_interpretations_batch(v_items,v_preview->>'preview_hash',v_authorization);
    EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
    IF v_error IS NULL OR v_error NOT LIKE 'EVIDENCE_PROMOTION_PROFILE_INVALID%' THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_DIGEST_TEST_FAILED: unknown profile accepted: %',v_error;
    END IF;
    RESET ROLE; SET session_replication_role=replica;
    UPDATE private.interpretation_promotion_authorization SET rule_profile=private.interpretation_promotion_profile(v_preview) WHERE id=v_authorization;
    SET session_replication_role=origin; SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub',v_other_actor::text,true);
    v_error:=NULL;
    BEGIN PERFORM red_promote_interpretations_batch(v_items,v_preview->>'preview_hash',v_authorization);
    EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
    IF v_error IS NULL OR v_error NOT LIKE 'EVIDENCE_PROMOTION_AUTHORIZATION_INVALID%' THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_DIGEST_TEST_FAILED: wrong actor accepted: %',v_error;
    END IF;
    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    RESET ROLE; SET session_replication_role=replica;
    UPDATE private.interpretation_promotion_authorization SET database_identity='{"database_name":"wrong","system_identifier":"wrong"}'::jsonb WHERE id=v_authorization;
    SET session_replication_role=origin; SET LOCAL ROLE authenticated;
    v_error:=NULL;
    BEGIN PERFORM red_promote_interpretations_batch(v_items,v_preview->>'preview_hash',v_authorization);
    EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
    IF v_error IS NULL OR v_error NOT LIKE 'EVIDENCE_PROMOTION_AUTHORIZATION_INVALID%' THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_DIGEST_TEST_FAILED: cross-db authorization accepted: %',v_error;
    END IF;
    RESET ROLE; SET session_replication_role=replica;
    UPDATE private.interpretation_promotion_authorization SET database_identity=private.interpretation_promotion_database_identity(),issued_at=clock_timestamp()-interval '2 seconds',expires_at=clock_timestamp()-interval '1 second' WHERE id=v_authorization;
    SET session_replication_role=origin; SET LOCAL ROLE authenticated;
    v_error:=NULL;
    BEGIN PERFORM red_promote_interpretations_batch(v_items,v_preview->>'preview_hash',v_authorization);
    EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
    IF v_error IS NULL OR v_error NOT LIKE 'EVIDENCE_PROMOTION_AUTHORIZATION_EXPIRED%' THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_DIGEST_TEST_FAILED: expired authorization accepted: %',v_error;
    END IF;
    RESET ROLE; SET session_replication_role=replica;
    UPDATE private.interpretation_promotion_authorization SET expires_at=clock_timestamp()+interval '5 minutes' WHERE id=v_authorization;
    SET session_replication_role=origin; SET LOCAL ROLE authenticated;
    v_receipt:=red_promote_interpretations_batch(
      v_items,v_preview->>'preview_hash',v_authorization
    );
    IF red_promote_interpretations_batch(v_items,v_preview->>'preview_hash',v_authorization)
         IS DISTINCT FROM v_receipt THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_DIGEST_TEST_FAILED: exact replay ændrede receipt';
    END IF;
    v_error:=NULL;
    BEGIN
      PERFORM red_authorize_interpretation_promotions(v_items,v_preview->>'preview_hash',
        '91000000-0000-0000-0000-000000000091',clock_timestamp()+interval '5 minutes');
    EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
    END;
    IF v_error IS NULL OR v_error NOT LIKE 'EVIDENCE_PROMOTION_NONCE_CONFLICT%' THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_DIGEST_TEST_FAILED: consumed nonce conflict missing: %',v_error;
    END IF;
    RESET ROLE;

    IF (SELECT count(*) FROM private.interpretation_promotion
         WHERE interpretation_id=v_accepted AND target_id=-987650091)<>1
       OR (SELECT count(*) FROM private.interpretation_promotion_batch
           WHERE promoted_by=v_actor AND requested_count=1
             AND rule_profile_hash ~ '^[0-9a-f]{64}$'
             AND authorization_id=v_authorization
             AND status='finalized'
             AND receipt_sha256 ~ '^[0-9a-f]{64}$')<>1
       OR v_receipt->>'terminal_status'<>'finalized'
       OR v_receipt->>'operation_id'<>(SELECT id::text
         FROM private.interpretation_promotion_batch WHERE authorization_id=v_authorization)
       OR v_receipt->'authorization_identity'->>'authority_id'<>v_authorization::text
       OR v_receipt->'database_identity'->>'database_name'<>current_database()
       OR v_receipt->'observed_counts'->>'promotions'<>'1'
       OR private.interpretation_promotion_batch_state(
            (v_receipt->>'operation_id')::uuid
          )->'verified_state' IS DISTINCT FROM v_receipt->'verified_state' THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_DIGEST_TEST_FAILED: promotion/batch mangler';
    END IF;
    SET session_replication_role=replica;
    UPDATE private.interpretation_promotion SET evidence=evidence || '{"postverify_drift":true}'::jsonb
      WHERE batch_id=(v_receipt->>'operation_id')::uuid;
    SET session_replication_role=origin;
    v_current:=private.interpretation_promotion_batch_state((v_receipt->>'operation_id')::uuid);
    IF v_current->'verified_state' IS NOT DISTINCT FROM v_receipt->'verified_state'
       OR (SELECT receipt FROM private.interpretation_promotion_batch WHERE id=(v_receipt->>'operation_id')::uuid)
            IS DISTINCT FROM v_receipt THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_DIGEST_TEST_FAILED: later drift did not preserve receipt/report state';
    END IF;
    IF current_setting('daa.evidence_promotion_keep_fixture',true) IS DISTINCT FROM 'on' THEN
      RAISE EXCEPTION 'ROLLBACK_EVIDENCE_PROMOTION_DIGEST_SUCCESS';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='ROLLBACK_EVIDENCE_PROMOTION_DIGEST_SUCCESS' THEN
      RAISE NOTICE 'OK: promotion-preview og batch bruger pgcrypto fra extensions';
    ELSE
      RAISE;
    END IF;
  END;
END $evidence_promotion_digest_success_test$;
