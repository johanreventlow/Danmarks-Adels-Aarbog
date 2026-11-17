-- Operationen record_persona (persona for helpost uden tekst): kan autoriseres, tælles ved finalize, aflæses med
-- red_reimport_batch_result og afvises af de generelle fortrydelser. Writeren selv afprøves andetsteds.
-- Kræver kontrakt v2 (reimport-writer-v2-bootstrap.sql). Alt syntetisk med negative id'er; én transaktion, rulles tilbage.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.expect_error(p_sql text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN
    IF SQLERRM IS NULL OR SQLERRM NOT LIKE p_token||'%' THEN RAISE EXCEPTION 'RECORD_PERSONA_REG_TEST_WRONG_ERROR: expected % got %', p_token, SQLERRM; END IF; RETURN; END;
  RAISE EXCEPTION 'RECORD_PERSONA_REG_TEST_NO_ERROR: expected %', p_token;
END $$;

-- Som expect_error, men kører udsagnet som authenticated (redaktøren er allerede sat i request.jwt.claim.sub).
CREATE FUNCTION pg_temp.expect_error_as_editor(p_sql text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role','authenticated',true);
  BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN
    RESET role;
    IF SQLERRM IS NULL OR SQLERRM NOT LIKE p_token||'%' THEN RAISE EXCEPTION 'RECORD_PERSONA_REG_TEST_WRONG_ERROR: expected % got %', p_token, SQLERRM; END IF; RETURN; END;
  RESET role;
  RAISE EXCEPTION 'RECORD_PERSONA_REG_TEST_NO_ERROR: expected %', p_token;
END $$;

-- 1. Autorisationens form (ren validering, ingen tilstand).
DO $validate$
BEGIN
  PERFORM private.validate_reimport_authorization_payload(
    '{"person_creates":0,"source_evidence":0,"record_personas":2}'::jsonb,
    '{"record-persona:a":{},"record-persona:b":{}}'::jsonb);
  -- 13 nøgler er det højeste antal
  PERFORM private.validate_reimport_authorization_payload(
    '{"person_creates":0,"source_evidence":0,"legacy_migrations":0,"clause_evidence":0,"interpretation_proposals":0,"clause_revisions":0,"relation_personas":0,"relation_person_creates":0,"relation_dispositions":0,"source_text_revision":0,"publication_personas":0,"publication_identities":0,"record_personas":0}'::jsonb,
    '{}'::jsonb);
  -- én for mange, for få, forkert prefix, forkert type og ukendt nøgle afvises
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"record_personas":1}','{"record-persona:a":{},"record-persona:b":{}}')$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"record_personas":2}','{"record-persona:a":{}}')$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"record_personas":1}','{"record-personas:a":{}}')$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"record_personas":1}','{"publication-persona:a":{}}')$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"record_personas":"1"}','{"record-persona:a":{}}')$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"record_persona":0}','{}')$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  RAISE NOTICE 'OK: authorization validation';
END $validate$;

-- 2. Batch-kæden: authorize -> begin -> (events) -> finalize -> batch_result.
CREATE TEMP TABLE rp_state(tag text PRIMARY KEY, actor uuid, auth uuid, batch uuid);
GRANT ALL ON rp_state TO PUBLIC;

CREATE FUNCTION pg_temp.rp_batch(p_tag text, p_authorized int, p_events int, p_finalize boolean DEFAULT true)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_source bigint:=-6301; v_profile text:='fixture-rp-'||p_tag; v_config jsonb; v_sha text; v_actor uuid:='11000000-0000-0000-0000-0000000c0701';
  v_msha text:=encode(extensions.digest('manifest-rp:'||p_tag,'sha256'),'hex'); v_psha text:=encode(extensions.digest('preview-rp:'||p_tag,'sha256'),'hex');
  v_auth uuid; v_batch uuid; v_elements jsonb:='{}'::jsonb; i int;
BEGIN
  INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES(v_source,'Fixture rp','synthetic','1900','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  INSERT INTO auth.users(id,email) VALUES (v_actor,v_actor::text||'@rp.invalid') ON CONFLICT DO NOTHING;
  INSERT INTO public.profiles(id,rolle,navn,email) VALUES (v_actor,'redaktion','rp fixture',v_actor::text||'@rp.invalid') ON CONFLICT DO NOTHING;
  v_config:=jsonb_build_object('citation_label_template','Synthetic side {page_from}','extractor_version','record-persona-v1',
    'observation_extraction_method','clause_segment_v1','rendition_key','fixture-r1','rendition_kind','pdf_text_layer',
    'rendition_metadata',jsonb_build_object('edition','fixture'),'run_key_prefix','reimport-record-persona:','schema_version','clause-evidence-manifest-v1');
  v_sha:=private.reimport_canonical_json_sha256(v_config);
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES(v_source,v_profile,'record-persona-v1',v_sha,v_config);
  FOR i IN 1..p_authorized LOOP v_elements:=v_elements||jsonb_build_object('record-persona:k'||i,'{}'::jsonb); END LOOP;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(v_msha,v_psha,jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    v_source,v_profile,v_sha,jsonb_build_object('person_creates',0,'source_evidence',0,'record_personas',p_authorized),v_elements,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch:=public.red_begin_reimport(v_auth,v_msha,v_psha);
  RESET role;
  FOR i IN 1..p_events LOOP
    INSERT INTO private.reimport_event(batch_id,element_id,operation,source_record_key,payload,after_sha256)
    VALUES(v_batch,'record-persona:k'||i,'record_persona','k'||i,'{}'::jsonb,repeat('a',64));
  END LOOP;
  INSERT INTO rp_state VALUES(p_tag,v_actor,v_auth,v_batch);
  IF p_finalize THEN
    PERFORM set_config('role','authenticated',true);
    PERFORM public.red_finalize_reimport(v_batch);
    RESET role;
  END IF;
EXCEPTION WHEN OTHERS THEN RESET role; RAISE;
END $$;

DO $chain$
DECLARE s rp_state%ROWTYPE; v_res jsonb; v_auth uuid;
BEGIN
  PERFORM pg_temp.rp_batch('ok',2,2);
  SELECT * INTO s FROM rp_state WHERE tag='ok';
  IF (SELECT observed_counts FROM private.reimport_batch WHERE id=s.batch)
     IS DISTINCT FROM '{"person_creates":0,"source_evidence":0,"record_personas":2}'::jsonb THEN
    RAISE EXCEPTION 'RECORD_PERSONA_REG_TEST_OBSERVED'; END IF;

  -- finalize med 1 forventet og 2 events afvises
  PERFORM pg_temp.expect_error($q$SELECT pg_temp.rp_batch('bad',1,2)$q$,'REIMPORT_WRITER_FINALIZE_COUNT_MISMATCH');

  -- batch-resultatet aflæser den finaliserede batch
  PERFORM set_config('request.jwt.claim.sub',s.actor::text,true);
  PERFORM set_config('role','authenticated',true);
  v_res:=public.red_reimport_batch_result(s.auth,s.batch);
  RESET role;
  IF v_res->>'status'<>'finalized' THEN RAISE EXCEPTION 'RECORD_PERSONA_REG_TEST_RESULT_STATUS: %',v_res; END IF;
  IF (SELECT observed_counts->>'record_personas' FROM private.reimport_batch WHERE id=s.batch)::int<>2 THEN
    RAISE EXCEPTION 'RECORD_PERSONA_REG_TEST_RESULT_COUNT'; END IF;

  -- de generelle fortrydelser afviser en record_persona-batch
  PERFORM set_config('request.jwt.claim.sub',s.actor::text,true);
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport_reversal(s.batch,gen_random_uuid(),clock_timestamp()+interval '10 minutes');
  RESET role;
  PERFORM pg_temp.expect_error_as_editor(format($q$SELECT public.red_reverse_reimport(%L,%L)$q$,s.batch,v_auth),'REIMPORT_WRITER_REVERSAL_INVALID');
  PERFORM pg_temp.expect_error_as_editor(format($q$SELECT public.red_reverse_reimport_publication(%L,%L)$q$,s.batch,v_auth),'REIMPORT_WRITER_REVERSAL_INVALID');
  RAISE NOTICE 'OK: batch chain';
END $chain$;

-- 3. Eksisterende profilers hash er uændret (hentet fra main før ændringen); manglende profiler (ren schema.sql-base) springes over.
--    Kun ægte kilder (1 = 2018-20, 3 = 1939): andre tests committer syntetiske profiler med samme profile_id på syntetiske kilder.
DO $profiles$
DECLARE k record;
BEGIN
  FOR k IN SELECT * FROM (VALUES
      ('daa-1939-v50-production-write-v1','25349caff16f2c13002a4950e80fe8697ffcf49e196dbcd9d1550919caf52fd3'),
      ('daa-1939-clause-evidence-v1','2aa5a358063fdf98f19954a683279cc3cabfd3eb5d5dd9c7fdaf5e42571b66d7'),
      ('daa-2018-20-source-text-revision-v1','60c7deaa352a3d7916ef35aba160a8f602c931474dd093a0dd1d6873d0a16f45'),
      ('daa-1939-interpretation-proposal-v1','c6131dcc9655fd74abeb3de787592ee76a7fa17944a9b525b41a38bdd7acd6dc')
    ) AS t(profile_id,sha) LOOP
    IF EXISTS(SELECT 1 FROM private.reimport_writer_profile WHERE profile_id=k.profile_id AND source_id IN (1,3) AND profile_sha256<>k.sha) THEN
      RAISE EXCEPTION 'RECORD_PERSONA_REG_PROFILE_SHA_CHANGED: %',k.profile_id; END IF;
  END LOOP;
  RAISE NOTICE 'OK: profile hashes';
END $profiles$;

ROLLBACK;
