-- Trin 6b Task 1: operationerne publication_persona og publication_identity kan autoriseres, tælles ved finalize og
-- skrives i reimport_event.
-- Kræver kontrakt v2 (reimport-writer-v2-bootstrap.sql) som test-clause-revision.sql. Alt syntetisk; én transaktion,
-- rulles tilbage.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.expect_error(p_sql text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN
    IF SQLERRM IS NULL OR SQLERRM NOT LIKE p_token||'%' THEN RAISE EXCEPTION 'PUBLICATION_REG_TEST_WRONG_ERROR: expected % got %', p_token, SQLERRM; END IF; RETURN; END;
  RAISE EXCEPTION 'PUBLICATION_REG_TEST_NO_ERROR: expected %', p_token;
END $$;

-- 1. Autorisationens form (ren validering, ingen tilstand).
DO $validate$
DECLARE v_pp jsonb:='{"person_creates":0,"source_evidence":0,"publication_personas":2}'::jsonb;
BEGIN
  PERFORM private.validate_reimport_authorization_payload(v_pp,
    '{"publication-persona:a":{},"publication-persona:b":{}}'::jsonb);
  PERFORM private.validate_reimport_authorization_payload(
    '{"person_creates":0,"source_evidence":0,"publication_identities":2}'::jsonb,
    '{"publication-identity:a":{},"publication-identity:b":{}}'::jsonb);
  -- en batch med begge nøgler er tilladt af valideringen (writerne afgør, hvad en batch må rumme)
  PERFORM private.validate_reimport_authorization_payload(
    '{"person_creates":0,"source_evidence":0,"publication_personas":1,"publication_identities":1}'::jsonb,
    '{"publication-persona:a":{},"publication-identity:a":{}}'::jsonb);
  -- 12 nøgler er det højeste antal
  PERFORM private.validate_reimport_authorization_payload(
    '{"person_creates":0,"source_evidence":0,"legacy_migrations":0,"clause_evidence":0,"interpretation_proposals":0,"clause_revisions":0,"relation_personas":0,"relation_person_creates":0,"relation_dispositions":0,"source_text_revision":0,"publication_personas":0,"publication_identities":0}'::jsonb,
    '{}'::jsonb);
  -- én for mange, for få, forkert prefix, forkert type og ukendt nøgle afvises
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"publication_personas":1}','{"publication-persona:a":{},"publication-persona:b":{}}')$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"publication_personas":2}','{"publication-persona:a":{}}')$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"publication_personas":1}','{"publication-persons:a":{}}')$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"publication_personas":1}','{"publication-identity:a":{}}')$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"publication_identities":1}','{"publication-persona:a":{}}')$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"publication_identities":"1"}','{"publication-identity:a":{}}')$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"publication_other":0}','{}')$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  RAISE NOTICE 'OK: authorization validation';
END $validate$;

-- 2. Operationerne kan stå i reimport_event, og finalize tæller dem.
CREATE FUNCTION pg_temp.pub_batch(p_tag text, p_op text, p_key text, p_prefix text, p_authorized int, p_events int)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_source bigint:=-6201; v_profile text:='fixture-pub-'||p_tag; v_config jsonb; v_sha text; v_actor uuid:='11000000-0000-0000-0000-00000006b101';
  v_msha text:=encode(extensions.digest('manifest-pub:'||p_tag,'sha256'),'hex'); v_psha text:=encode(extensions.digest('preview-pub:'||p_tag,'sha256'),'hex');
  v_auth uuid; v_batch uuid; v_elements jsonb:='{}'::jsonb; i int;
BEGIN
  INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES(v_source,'Fixture pub','synthetic','1900','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  INSERT INTO auth.users(id,email) VALUES (v_actor,v_actor::text||'@6b.invalid') ON CONFLICT DO NOTHING;
  INSERT INTO public.profiles(id,rolle,navn,email) VALUES (v_actor,'redaktion','6b fixture',v_actor::text||'@6b.invalid') ON CONFLICT DO NOTHING;
  v_config:=jsonb_build_object('citation_label_template','Synthetic side {page_from}','extractor_version','publication-v1',
    'observation_extraction_method','clause_segment_v1','rendition_key','fixture-r1','rendition_kind','pdf_text_layer',
    'rendition_metadata',jsonb_build_object('edition','fixture'),'run_key_prefix','reimport-publication:','schema_version','clause-evidence-manifest-v1');
  v_sha:=private.reimport_canonical_json_sha256(v_config);
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES(v_source,v_profile,'publication-v1',v_sha,v_config);
  FOR i IN 1..p_authorized LOOP v_elements:=v_elements||jsonb_build_object(p_prefix||i,'{}'::jsonb); END LOOP;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(v_msha,v_psha,jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    v_source,v_profile,v_sha,jsonb_build_object('person_creates',0,'source_evidence',0,p_key,p_authorized),v_elements,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch:=public.red_begin_reimport(v_auth,v_msha,v_psha);
  RESET role;
  FOR i IN 1..p_events LOOP
    INSERT INTO private.reimport_event(batch_id,element_id,operation,source_record_key,payload,after_sha256)
    VALUES(v_batch,p_prefix||i,p_op,'k'||i,'{}'::jsonb,repeat('a',64));
  END LOOP;
  PERFORM set_config('role','authenticated',true);
  PERFORM public.red_finalize_reimport(v_batch);
  RESET role;
  IF (SELECT observed_counts->>p_key FROM private.reimport_batch WHERE id=v_batch)::int<>p_events THEN
    RAISE EXCEPTION 'PUBLICATION_REG_TEST_OBSERVED: %',p_key; END IF;
END $$;

DO $finalize$
BEGIN
  PERFORM pg_temp.pub_batch('pp-ok','publication_persona','publication_personas','publication-persona:',2,2);
  -- publication_identity: tællingen stemmer, men finalize efterprøver derefter kandidatkørslen (Task 6); events uden
  -- kørsel afvises. Tællingen ved en gyldig C-batch afprøves i test-publication-identity.sql (fuld kæde).
  PERFORM pg_temp.expect_error($q$SELECT pg_temp.pub_batch('pi-ok','publication_identity','publication_identities','publication-identity:',2,2)$q$,'PUBLICATION_IDENTITY_RUN_STALE');
  -- ét forventet, men to events: finalize afviser. Fixturen autoriserer 1 element og indsætter 2 events.
  PERFORM pg_temp.expect_error($q$SELECT pg_temp.pub_batch('pp-bad','publication_persona','publication_personas','publication-persona:',1,2)$q$,'REIMPORT_WRITER_FINALIZE_COUNT_MISMATCH');
  PERFORM pg_temp.expect_error($q$SELECT pg_temp.pub_batch('pi-bad','publication_identity','publication_identities','publication-identity:',1,2)$q$,'REIMPORT_WRITER_FINALIZE_COUNT_MISMATCH');
  RAISE NOTICE 'OK: finalize counts';
END $finalize$;

-- Profilen daa-1939-publication-v1 og de eksisterende profilers uændrede hash afprøves i test-reimport-profile-seeds.sql
-- (seedene kræver, at kilde 3 findes, når db-migrations.sql kører; en ren schema.sql-base har dem ikke).

ROLLBACK;
