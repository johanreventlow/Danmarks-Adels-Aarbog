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
      'private.add_interpretation_promotion_rule_version(text,text,text,text,text,text,boolean,boolean,boolean,text,text)'::regprocedure
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

-- En gyldig, kildebunden promotion skal gennem begge SHA-256-stier med
-- Supabases faktiske pgcrypto-layout. Hele fixturen rulles tilbage, så testen
-- også kan køres mod en database med eksisterende data.
DO $evidence_promotion_digest_success_test$
DECLARE
  v_actor uuid := '11000000-0000-0000-0000-000000000091';
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
BEGIN
  BEGIN
    INSERT INTO auth.users(id,email)
      VALUES (v_actor,'promotion-digest-success@test.invalid');
    INSERT INTO profiles(id,rolle,navn,email)
      VALUES (v_actor,'redaktion','Promotion Digest Success',
              'promotion-digest-success@test.invalid');
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
    PERFORM private.decide_source_persona_identity(v_persona,-987650091,0,'accepted','{"basis":"web_detail","note":"digest success regression"}','human');
    SET LOCAL ROLE authenticated;
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
    PERFORM red_promote_interpretations_batch(v_items,v_preview->>'preview_hash');
    RESET ROLE;

    IF (SELECT count(*) FROM private.interpretation_promotion
         WHERE interpretation_id=v_accepted AND target_id=-987650091)<>1
       OR (SELECT count(*) FROM private.interpretation_promotion_batch
           WHERE promoted_by=v_actor AND requested_count=1
             AND rule_profile_hash ~ '^[0-9a-f]{64}$')<>1 THEN
      RAISE EXCEPTION 'EVIDENCE_PROMOTION_DIGEST_TEST_FAILED: promotion/batch mangler';
    END IF;
    RAISE EXCEPTION 'ROLLBACK_EVIDENCE_PROMOTION_DIGEST_SUCCESS';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='ROLLBACK_EVIDENCE_PROMOTION_DIGEST_SUCCESS' THEN
      RAISE NOTICE 'OK: promotion-preview og batch bruger pgcrypto fra extensions';
    ELSE
      RAISE;
    END IF;
  END;
END $evidence_promotion_digest_success_test$;

-- Trin 6c-2b (spec 2026-11-02): højst én gældende binding pr. påstand. En anden fortolkning (en anden
-- interpretation_key) med en gyldig binding på påstanden spærrer med ALREADY_BOUND_OTHER, uanset kilde og persona;
-- to forskellige nøgler i samme batch mod samme påstand afvises begge. Versioner af samme nøgle er ikke »anden«.
-- Syntetisk: kilde -4401 og -4403 spiller rollerne som to udgaver. Rulles tilbage.
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql

-- Et accepteret dødsforslag fra p_post's hovedperson-persona; returnerer den gældende version.
CREATE FUNCTION pg_temp.ebo_forslag(p_source bigint,p_post jsonb,p_run uuid,p_value text,p_actor uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_int uuid:=gen_random_uuid(); v_key uuid:=gen_random_uuid(); v_cur uuid;
BEGIN
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
    predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES (v_int,v_key,1,p_source,(p_post->>'principal')::uuid,'property','person.death',to_jsonb(p_value),
      '1.0','source_statement',1,'proposed','fixture',p_run);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_int,(p_post->'clauses'->>0)::uuid,'supporting',1);
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_decide_interpretation(v_int,1,'accepted','{"basis":"en binding pr. paastand"}');
  RESET ROLE;
  PERFORM set_config('app.change_set_id','',true);
  SELECT ic.id INTO v_cur FROM private.interpretation_current ic WHERE ic.interpretation_key=v_key;
  RETURN v_cur;
END $$;

-- Et afklaret dødsfaktum med én påstand for p_person.
CREATE FUNCTION pg_temp.ebo_paastand(p_person bigint,p_value text) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_fact bigint; v_a bigint;
BEGIN
  INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',p_person,'død') RETURNING id INTO v_fact;
  INSERT INTO assertion(target_type,target_id,date_raw,calendar,uforanderlig)
    VALUES ('fact',v_fact,p_value,'gregoriansk',true) RETURNING id INTO v_a;
  INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_fact,v_a,'afklaret');
  RETURN v_a;
END $$;

-- Elementerne (fortolkning, påstand) som batch-input.
CREATE FUNCTION pg_temp.ebo_items(p_pairs jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_agg(jsonb_build_object('interpretation_id',e->>0,'target_type','assertion','target_id',(e->>1)::bigint)
           ORDER BY o)
    FROM jsonb_array_elements(p_pairs) WITH ORDINALITY AS x(e,o)
$$;

-- Previewets reason_code pr. element (NULL = gyldigt), kaldt som redaktør.
CREATE FUNCTION pg_temp.ebo_reasons(p_items jsonb) RETURNS text[] LANGUAGE plpgsql AS $$
DECLARE pv jsonb;
BEGIN
  SET LOCAL ROLE authenticated;
  pv:=public.red_preview_interpretation_promotions(p_items);
  RESET ROLE;
  RETURN ARRAY(SELECT i->>'reason_code' FROM jsonb_array_elements(pv->'items') WITH ORDINALITY AS x(i,o) ORDER BY o);
END $$;

-- Batchen som redaktør med friskt preview; returnerer NULL ved succes, ellers fejlteksten (intet skrevet).
CREATE FUNCTION pg_temp.ebo_promote(p_items jsonb) RETURNS text LANGUAGE plpgsql AS $$
DECLARE pv jsonb;
BEGIN
  BEGIN
    SET LOCAL ROLE authenticated;
    pv:=public.red_preview_interpretation_promotions(p_items);
    PERFORM public.red_promote_interpretations_batch(p_items,pv->>'preview_hash');
    RESET ROLE;
    RETURN NULL;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RETURN SQLERRM;
  END;
END $$;

DO $en_binding_pr_paastand$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-0000006c2b44'; v_p bigint:=-4401;
  s1 jsonb; s3 jsonb; p1 jsonb; p3a jsonb; p3b jsonb; r1 uuid; r3 uuid;
  a_a bigint; a_b bigint; a_c bigint; a_d bigint; a_e bigint; a_f bigint; a_g bigint; a_h bigint; a_x bigint;
  i_a1 uuid; i_a2 uuid; i_b1 uuid; i_b2 uuid; i_c1 uuid; i_c2 uuid; i_d1 uuid; i_d3 uuid; i_e1 uuid; i_e3 uuid;
  i_f1 uuid; i_f2 uuid; i_g uuid; i_h_old uuid; i_h uuid; i_x uuid; v_v2 uuid;
  v_err text; v_reasons text[]; n_batch bigint;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (v_p,false,false,'en binding');
  s1:=pg_temp.f5b_source(-4401); r1:=(s1->>'run')::uuid;
  s3:=pg_temp.f5b_source(-4403); r3:=(s3->>'run')::uuid;
  p1:=pg_temp.f5b_post(-4401,s1,'P4401','Anna Alfa. Død 1850.',ARRAY['Død 1850.'],v_p,v_actor);
  p3a:=pg_temp.f5b_post(-4403,s3,'P4403A','Anna Alfa. Død 1850.',ARRAY['Død 1850.'],v_p,v_actor);
  p3b:=pg_temp.f5b_post(-4403,s3,'P4403B','Anna Alfa. Død 1850.',ARRAY['Død 1850.'],v_p,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p1->>'principal')::uuid);
  PERFORM pg_temp.f2a_event_for_state((p3a->>'principal')::uuid);
  PERFORM pg_temp.f2a_event_for_state((p3b->>'principal')::uuid);
  a_a:=pg_temp.ebo_paastand(v_p,'1850'); a_b:=pg_temp.ebo_paastand(v_p,'1850');
  a_c:=pg_temp.ebo_paastand(v_p,'1850'); a_d:=pg_temp.ebo_paastand(v_p,'1850');
  a_e:=pg_temp.ebo_paastand(v_p,'1850'); a_f:=pg_temp.ebo_paastand(v_p,'1850');
  a_g:=pg_temp.ebo_paastand(v_p,'1850'); a_h:=pg_temp.ebo_paastand(v_p,'1850');
  a_x:=pg_temp.ebo_paastand(v_p,'1850');
  i_a1:=pg_temp.ebo_forslag(-4403,p3a,r3,'1850',v_actor); i_a2:=pg_temp.ebo_forslag(-4403,p3b,r3,'1850',v_actor);
  i_b1:=pg_temp.ebo_forslag(-4403,p3a,r3,'1850',v_actor); i_b2:=pg_temp.ebo_forslag(-4403,p3b,r3,'1850',v_actor);
  i_c1:=pg_temp.ebo_forslag(-4403,p3a,r3,'1850',v_actor); i_c2:=pg_temp.ebo_forslag(-4403,p3a,r3,'1850',v_actor);
  i_d1:=pg_temp.ebo_forslag(-4401,p1,r1,'1850',v_actor); i_d3:=pg_temp.ebo_forslag(-4403,p3a,r3,'1850',v_actor);
  i_e1:=pg_temp.ebo_forslag(-4401,p1,r1,'1850',v_actor); i_e3:=pg_temp.ebo_forslag(-4403,p3a,r3,'1850',v_actor);
  i_f1:=pg_temp.ebo_forslag(-4401,p1,r1,'1850',v_actor); i_f2:=pg_temp.ebo_forslag(-4403,p3a,r3,'1850',v_actor);
  i_g:=pg_temp.ebo_forslag(-4403,p3a,r3,'1850',v_actor);
  i_x:=pg_temp.ebo_forslag(-4403,p3b,r3,'1850',v_actor);
  -- i_h: den gældende version; i_h_old: den overhalede version 1 af samme nøgle.
  i_h:=pg_temp.ebo_forslag(-4403,p3a,r3,'1850',v_actor);
  SELECT supersedes_id INTO i_h_old FROM private.interpretation WHERE id=i_h;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF i_h_old IS NULL OR i_h_old=i_h THEN RAISE EXCEPTION 'EBO_TEST_FIXTURE: ingen overhalet version'; END IF;

  -- (1) To personas fra samme kilde: første batch binder, anden afvises og skriver intet.
  IF pg_temp.ebo_promote(pg_temp.ebo_items(jsonb_build_array(jsonb_build_array(i_a1,a_a)))) IS NOT NULL THEN
    RAISE EXCEPTION 'EBO_TEST_FAILED: første binding (1)';
  END IF;
  v_reasons:=pg_temp.ebo_reasons(pg_temp.ebo_items(jsonb_build_array(jsonb_build_array(i_a2,a_a))));
  IF v_reasons IS DISTINCT FROM ARRAY['ALREADY_BOUND_OTHER'] THEN
    RAISE EXCEPTION 'EBO_TEST_FAILED: (1) preview %',v_reasons;
  END IF;
  SELECT count(*) INTO n_batch FROM private.interpretation_promotion_batch;
  v_err:=pg_temp.ebo_promote(pg_temp.ebo_items(jsonb_build_array(jsonb_build_array(i_a2,a_a))));
  IF v_err IS DISTINCT FROM 'ALREADY_BOUND_OTHER' THEN RAISE EXCEPTION 'EBO_TEST_FAILED: (1) batch %',v_err; END IF;
  IF (SELECT count(*) FROM private.interpretation_promotion WHERE target_type='assertion' AND target_id=a_a)<>1
     OR (SELECT count(*) FROM private.interpretation_promotion_batch)<>n_batch THEN
    RAISE EXCEPTION 'EBO_TEST_FAILED: (1) den afviste batch skrev';
  END IF;
  -- Samme nøgle igen er stadig ALREADY_PROMOTED (rækkefølgen: ALREADY_PROMOTED før ALREADY_BOUND_OTHER).
  v_reasons:=pg_temp.ebo_reasons(pg_temp.ebo_items(jsonb_build_array(jsonb_build_array(i_a1,a_a))));
  IF v_reasons IS DISTINCT FROM ARRAY['EVIDENCE_PROMOTION_ALREADY_PROMOTED'] THEN
    RAISE EXCEPTION 'EBO_TEST_FAILED: (1) genpromovering %',v_reasons;
  END IF;

  -- (2) De samme to personas i én batch: begge afvist, intet skrevet.
  v_reasons:=pg_temp.ebo_reasons(pg_temp.ebo_items(jsonb_build_array(jsonb_build_array(i_b1,a_b),jsonb_build_array(i_b2,a_b))));
  IF v_reasons IS DISTINCT FROM ARRAY['ALREADY_BOUND_OTHER','ALREADY_BOUND_OTHER'] THEN
    RAISE EXCEPTION 'EBO_TEST_FAILED: (2) preview %',v_reasons;
  END IF;
  v_err:=pg_temp.ebo_promote(pg_temp.ebo_items(jsonb_build_array(jsonb_build_array(i_b1,a_b),jsonb_build_array(i_b2,a_b))));
  IF v_err IS DISTINCT FROM 'ALREADY_BOUND_OTHER'
     OR EXISTS (SELECT 1 FROM private.interpretation_promotion WHERE target_type='assertion' AND target_id=a_b) THEN
    RAISE EXCEPTION 'EBO_TEST_FAILED: (2) batch %',v_err;
  END IF;

  -- (3) To fortolkninger fra samme persona i én batch: begge afvist.
  v_reasons:=pg_temp.ebo_reasons(pg_temp.ebo_items(jsonb_build_array(jsonb_build_array(i_c1,a_c),jsonb_build_array(i_c2,a_c))));
  IF v_reasons IS DISTINCT FROM ARRAY['ALREADY_BOUND_OTHER','ALREADY_BOUND_OTHER'] THEN
    RAISE EXCEPTION 'EBO_TEST_FAILED: (3) preview %',v_reasons;
  END IF;
  v_err:=pg_temp.ebo_promote(pg_temp.ebo_items(jsonb_build_array(jsonb_build_array(i_c1,a_c),jsonb_build_array(i_c2,a_c))));
  IF v_err IS DISTINCT FROM 'ALREADY_BOUND_OTHER'
     OR EXISTS (SELECT 1 FROM private.interpretation_promotion WHERE target_type='assertion' AND target_id=a_c) THEN
    RAISE EXCEPTION 'EBO_TEST_FAILED: (3) batch %',v_err;
  END IF;

  -- (4) På tværs af kilder, begge veje: en binding fra -4401 spærrer -4403, og omvendt.
  IF pg_temp.ebo_promote(pg_temp.ebo_items(jsonb_build_array(jsonb_build_array(i_d1,a_d)))) IS NOT NULL
     OR pg_temp.ebo_promote(pg_temp.ebo_items(jsonb_build_array(jsonb_build_array(i_e3,a_e)))) IS NOT NULL THEN
    RAISE EXCEPTION 'EBO_TEST_FAILED: første binding (4)';
  END IF;
  v_reasons:=pg_temp.ebo_reasons(pg_temp.ebo_items(jsonb_build_array(jsonb_build_array(i_d3,a_d),jsonb_build_array(i_e1,a_e))));
  IF v_reasons IS DISTINCT FROM ARRAY['ALREADY_BOUND_OTHER','ALREADY_BOUND_OTHER'] THEN
    RAISE EXCEPTION 'EBO_TEST_FAILED: (4) preview %',v_reasons;
  END IF;
  v_err:=pg_temp.ebo_promote(pg_temp.ebo_items(jsonb_build_array(jsonb_build_array(i_d3,a_d))));
  IF v_err IS DISTINCT FROM 'ALREADY_BOUND_OTHER' THEN RAISE EXCEPTION 'EBO_TEST_FAILED: (4) batch %',v_err; END IF;

  -- (5) Kun en GYLDIG binding spærrer: når den anden nøgle har fået en ny version, er dens binding ikke gældende.
  IF pg_temp.ebo_promote(pg_temp.ebo_items(jsonb_build_array(jsonb_build_array(i_f1,a_f)))) IS NOT NULL THEN
    RAISE EXCEPTION 'EBO_TEST_FAILED: første binding (5)';
  END IF;
  v_v2:=gen_random_uuid();
  INSERT INTO private.interpretation(id,interpretation_key,version,supersedes_id,source_id,source_persona_id,
    interpretation_kind,predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
  SELECT v_v2,ic.interpretation_key,ic.version+1,ic.id,ic.source_id,ic.source_persona_id,ic.interpretation_kind,
         ic.predicate,ic.value,ic.schema_version,ic.derivation_kind,ic.confidence,'proposed',ic.method,ic.extraction_run_id
    FROM private.interpretation_current ic
   WHERE ic.interpretation_key=(SELECT interpretation_key FROM private.interpretation WHERE id=i_f1);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_v2,(p1->'clauses'->>0)::uuid,'supporting',1);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.ebo_promote(pg_temp.ebo_items(jsonb_build_array(jsonb_build_array(i_f2,a_f)))) IS NOT NULL THEN
    RAISE EXCEPTION 'EBO_TEST_FAILED: (5) en ugyldig binding spærrede';
  END IF;

  -- (6) Et ukendt id i batchen smitter ikke et gyldigt element; to versioner af samme nøgle er ikke »anden«.
  v_reasons:=pg_temp.ebo_reasons(pg_temp.ebo_items(jsonb_build_array(
    jsonb_build_array(gen_random_uuid(),a_g),jsonb_build_array(i_g,a_g))));
  IF v_reasons IS DISTINCT FROM ARRAY['EVIDENCE_INTERPRETATION_NOT_FOUND',NULL] THEN
    RAISE EXCEPTION 'EBO_TEST_FAILED: (6) ukendt id %',v_reasons;
  END IF;
  v_reasons:=pg_temp.ebo_reasons(pg_temp.ebo_items(jsonb_build_array(jsonb_build_array(i_h_old,a_h),jsonb_build_array(i_h,a_h))));
  IF v_reasons IS DISTINCT FROM ARRAY['EVIDENCE_INTERPRETATION_NOT_CURRENT',NULL] THEN
    RAISE EXCEPTION 'EBO_TEST_FAILED: (6) versioner af samme nøgle %',v_reasons;
  END IF;

  -- (7) To nøgler mod hver sin påstand i én batch er stadig gyldige.
  IF pg_temp.ebo_promote(pg_temp.ebo_items(jsonb_build_array(jsonb_build_array(i_g,a_g),jsonb_build_array(i_x,a_x)))) IS NOT NULL THEN
    RAISE EXCEPTION 'EBO_TEST_FAILED: (7) to påstande i én batch';
  END IF;

  -- Højst én gældende binding pr. påstand i hele fixturen.
  IF EXISTS (SELECT 1 FROM private.interpretation_promotion p
              WHERE p.target_type='assertion' AND p.target_id IN (a_a,a_b,a_c,a_d,a_e,a_f,a_g,a_h,a_x)
                AND private.assertion_binding_current(p.id)
              GROUP BY p.target_id HAVING count(*)>1) THEN
    RAISE EXCEPTION 'EBO_TEST_FAILED: en påstand har flere gældende bindinger';
  END IF;
  RAISE NOTICE 'OK: højst én gældende binding pr. påstand (ALREADY_BOUND_OTHER)';
END $en_binding_pr_paastand$;
ROLLBACK;
