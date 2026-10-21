-- Trin 5a, Task 3: afgørelsens udgange, kandidatbinding, aktualitet, kildelås og den strukturelle guard.
CREATE EXTENSION IF NOT EXISTS dblink;

DO $identity_surface$
BEGIN
  IF to_regprocedure('public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: den offentlige kerne findes stadig';
  END IF;
  IF to_regprocedure('public.red_afgoer_source_persona(uuid,integer,text,bigint,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: femarguments-wrapperen findes stadig';
  END IF;
  IF has_function_privilege('authenticated','private.decide_source_persona_identity(uuid,bigint,integer,text,jsonb,text)','EXECUTE')
     OR has_function_privilege('anon','private.decide_source_persona_identity(uuid,bigint,integer,text,jsonb,text)','EXECUTE') THEN
    RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: kernen kan kaldes af en klientrolle';
  END IF;
  IF NOT has_function_privilege('authenticated','public.red_afgoer_source_persona(uuid,integer,text,bigint,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: wrapperen kan ikke kaldes af authenticated';
  END IF;
  RAISE NOTICE 'OK: funktionsfladen — privat kerne, kun seksarguments-wrapperen for klienter';
END $identity_surface$;

DO $identity_decision$
DECLARE
  v_actor uuid := '11000000-0000-0000-0000-000000005a03';
  v_run uuid := '22000000-0000-0000-0000-000000005a03';
  v_rend uuid := '33000000-0000-0000-0000-000000005a03';
  v_occ uuid := '55000000-0000-0000-0000-000000005a03';
  v_obs uuid := '66000000-0000-0000-0000-000000005a03';
  v_ps uuid[] := ARRAY['88000000-0000-0000-0000-000000005a31','88000000-0000-0000-0000-000000005a32',
                       '88000000-0000-0000-0000-000000005a33','88000000-0000-0000-0000-000000005a34',
                       '88000000-0000-0000-0000-000000005a35','88000000-0000-0000-0000-000000005a36',
                       '88000000-0000-0000-0000-000000005a37']::uuid[];
  v_old_run uuid; v_new_run uuid; v_cand uuid; v_cand5 uuid; v_ev jsonb; v_i int; v_new bigint; v_state text; v_err text;
BEGIN
  BEGIN
    INSERT INTO auth.users(id,email) VALUES (v_actor,'5a-decide@test.invalid');
    INSERT INTO profiles(id,rolle,navn,email) VALUES (v_actor,'redaktion','5a decide','5a-decide@test.invalid');
    INSERT INTO person(id,levende,privat,status) VALUES (-987655031,false,false,'5a'),(-987655032,false,false,'5a');
    INSERT INTO source(id,titel,import_key) VALUES (-987655031,'5a D','verify:5a:d');
    INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
      VALUES (v_run,-987655031,'5a-run-d','1.0','verify','verify',repeat('9',64),'{}');
    INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata)
      VALUES (v_rend,-987655031,'5a-rend','text_layer',repeat('8',64),'{}');
    INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
      verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
      VALUES (v_occ,v_rend,'5a-occ',1,1,0,9,'Anna Test','phys-5a','struct-5a',v_run);
    INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
      verbatim_text,quality_status,extraction_method,extraction_run_id)
      VALUES (v_obs,v_occ,'name_clause',1,1,0,9,'Anna Test','clear','verify',v_run);
    FOR v_i IN 1..7 LOOP
      INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES (v_ps[v_i],-987655031,'5a-d'||v_i,v_run);
      INSERT INTO private.source_mention(id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
        VALUES (('70000000-0000-0000-0000-000000005a3'||v_i)::uuid,v_obs,'person',0,9,'Anna Test',v_run);
      INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
        VALUES (v_ps[v_i],('70000000-0000-0000-0000-000000005a3'||v_i)::uuid,'principal',1);
    END LOOP;
    INSERT INTO private.source_persona_identity_candidate_run(source_id,generator_version,config,config_sha256,input_spec,
      input_sha256,candidates_sha256,persona_count,candidate_count,created_by,created_by_name)
      VALUES (-987655031,'t','{}',repeat('a',64),'{"mode":"undecided"}',repeat('b',64),repeat('c',64),6,2,v_actor,'t')
      RETURNING id INTO v_old_run;
    INSERT INTO private.source_persona_identity_candidate(run_id,source_persona_id,candidate_person_id,rank,score,tier,basis)
      VALUES (v_old_run,v_ps[1],-987655031,1,0.92,'auto','{"signals":["name"]}') RETURNING id INTO v_cand;
    INSERT INTO private.source_persona_identity_candidate(run_id,source_persona_id,candidate_person_id,rank,score,tier,basis)
      VALUES (v_old_run,v_ps[5],-987655032,1,0.7,'review','{"signals":["name"]}') RETURNING id INTO v_cand5;

    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    SET LOCAL ROLE authenticated;
    -- 1 same med fulgt kandidat fra gældende kørsel (web)
    PERFORM red_afgoer_source_persona(v_ps[1],0,'same',-987655031,'kandidat fulgt',
      jsonb_build_object('candidate_id',v_cand,'run_id',v_old_run));
    -- 2 different, 3 unresolved, 4 new_person_needed (ark)
    PERFORM red_afgoer_source_persona(v_ps[2],0,'different',NULL,'ikke ham','{}');
    PERFORM red_afgoer_source_persona(v_ps[3],0,'unresolved',NULL,'uklart','{}');
    PERFORM red_afgoer_source_persona(v_ps[4],0,'new_person_needed',NULL,'findes ikke',
      jsonb_build_object('basis','human_sheet','sheet_sha256',repeat('e',64),'rows_sha256',repeat('f',64),'line',7));
    -- ugyldige kontekster og kandidater
    FOR v_err IN SELECT unnest(ARRAY['uden_run','fremmed','ark_uden_hash','ukendt_noegle','klient_kerne']) LOOP
      v_state:=NULL;
      BEGIN
        IF v_err='uden_run' THEN
          PERFORM red_afgoer_source_persona(v_ps[5],0,'same',-987655032,'x',jsonb_build_object('candidate_id',v_cand5));
        ELSIF v_err='fremmed' THEN
          PERFORM red_afgoer_source_persona(v_ps[5],0,'same',-987655031,'x',jsonb_build_object('candidate_id',v_cand,'run_id',v_old_run));
        ELSIF v_err='ark_uden_hash' THEN
          PERFORM red_afgoer_source_persona(v_ps[5],0,'different',NULL,'x','{"basis":"human_sheet"}');
        ELSIF v_err='ukendt_noegle' THEN
          PERFORM red_afgoer_source_persona(v_ps[5],0,'different',NULL,'x','{"batch_id":"00000000-0000-0000-0000-000000000001"}');
        ELSE
          PERFORM private.decide_source_persona_identity(v_ps[5],-987655032,0,'accepted','{"basis":"web_detail"}','human');
        END IF;
        RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: % blev accepteret',v_err;
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
        IF (v_err='klient_kerne' AND v_state<>'42501')
           OR (v_err<>'klient_kerne' AND SQLERRM IS DISTINCT FROM (CASE v_err
                 WHEN 'fremmed' THEN 'EVIDENCE_IDENTITY_CANDIDATE_MISMATCH' ELSE 'EVIDENCE_IDENTITY_DECISION_INVALID' END)) THEN
          RAISE;
        END IF;
      END;
    END LOOP;
    RESET ROLE;

    -- en nyere kørsel gør v_cand5's kørsel forældet: afgørelsen skal afvises
    INSERT INTO private.source_persona_identity_candidate_run(source_id,generator_version,config,config_sha256,input_spec,
      input_sha256,candidates_sha256,persona_count,candidate_count,created_by,created_by_name)
      VALUES (-987655031,'t','{}',repeat('a',64),'{"mode":"undecided"}',repeat('d',64),repeat('c',64),6,0,v_actor,'t')
      RETURNING id INTO v_new_run;
    SET LOCAL ROLE authenticated;
    BEGIN
      PERFORM red_afgoer_source_persona(v_ps[5],0,'same',-987655032,'forældet',jsonb_build_object('candidate_id',v_cand5,'run_id',v_old_run));
      RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: forældet kørsel accepteret';
    EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'EVIDENCE_IDENTITY_CANDIDATE_RUN_STALE' THEN RAISE; END IF; END;
    RESET ROLE;

    -- kernen direkte (superbruger = serverfunktionernes rettighed): hver oprindelse og dens krav
    -- fast 1:1-kobling til person -987655032 for postnøglen 5a-R1 i kilden (til legacy_match)
    INSERT INTO public.person_external_id(person_id,source_id,record_key) VALUES (-987655032,-987655031,'5a-R1');
    FOR v_err IN SELECT unnest(ARRAY['human_fri','create_status','create_basis','create_uden_kvittering',
                                     'legacy_forkert_person','legacy_uden_autoritet','reversal_uden','ukendt']) LOOP
      BEGIN
        IF v_err='human_fri' THEN
          PERFORM private.decide_source_persona_identity(v_ps[5],-987655032,0,'accepted','{"basis":"fri tekst"}','human');
        ELSIF v_err='create_status' THEN
          PERFORM private.decide_source_persona_identity(v_ps[5],NULL,0,'rejected','{"batch_id":"00000000-0000-0000-0000-000000000001"}','person_create');
        ELSIF v_err='create_basis' THEN
          PERFORM private.decide_source_persona_identity(v_ps[5],-987655032,0,'accepted','{"batch_id":"00000000-0000-0000-0000-000000000001","basis":"web_detail"}','person_create');
        ELSIF v_err='create_uden_kvittering' THEN   -- eksisterende person, ingen kvittering
          PERFORM private.decide_source_persona_identity(v_ps[5],-987655032,0,'accepted','{"batch_id":"00000000-0000-0000-0000-000000000001"}','person_create');
        ELSIF v_err='legacy_forkert_person' THEN     -- evidensen peger på en anden person end koblingen
          PERFORM private.decide_source_persona_identity(v_ps[6],-987655031,0,'accepted',
            '{"authority":"person_external_id","person_external_id":{"person_id":-987655031,"source_id":-987655031,"record_key":"5a-R1"}}','legacy_match');
        ELSIF v_err='legacy_uden_autoritet' THEN
          PERFORM private.decide_source_persona_identity(v_ps[6],-987655032,0,'accepted','{"batch_id":"00000000-0000-0000-0000-000000000001"}','legacy_match');
        ELSIF v_err='reversal_uden' THEN
          PERFORM private.decide_source_persona_identity(v_ps[1],NULL,1,'superseded','{"note":"x"}','reversal');
        ELSE
          PERFORM private.decide_source_persona_identity(v_ps[5],-987655032,0,'accepted','{"batch_id":"00000000-0000-0000-0000-000000000001"}','batch');
        END IF;
        RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: kerne-% accepteret',v_err;
      EXCEPTION WHEN OTHERS THEN
        IF SQLERRM IS DISTINCT FROM (CASE v_err WHEN 'ukendt' THEN 'EVIDENCE_IDENTITY_ORIGIN_INVALID'
             WHEN 'create_uden_kvittering' THEN 'EVIDENCE_IDENTITY_CREATE_RECEIPT_MISSING'
             ELSE 'EVIDENCE_IDENTITY_BASIS_REQUIRED' END) THEN RAISE; END IF;
      END;
    END LOOP;
    -- oprettelse med kvittering (også inde i en subtransaktion) tillades; kvitteringen forbruges
    BEGIN
      v_new := private.insert_person_with_receipt(true,'5a oprettet nu');
      PERFORM private.decide_source_persona_identity(v_ps[5],v_new,0,'accepted','{"batch_id":"00000000-0000-0000-0000-000000000001"}','person_create');
    EXCEPTION WHEN OTHERS THEN RAISE;   -- EXCEPTION-klausulen gør blokken til en subtransaktion
    END;
    BEGIN PERFORM private.decide_source_persona_identity(v_ps[7],v_new,0,'accepted','{"batch_id":"00000000-0000-0000-0000-000000000001"}','person_create');
      RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: kvittering genbrugt';
    EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'EVIDENCE_IDENTITY_CREATE_RECEIPT_MISSING' THEN RAISE; END IF; END;
    PERFORM private.decide_source_persona_identity(v_ps[5],NULL,1,'superseded','{"reversed_batch_id":"00000000-0000-0000-0000-000000000001"}','reversal');
    -- 149b's faste 1:1-kobling tillades som legacy_match
    PERFORM private.decide_source_persona_identity(v_ps[6],-987655032,0,'accepted',
      '{"authority":"person_external_id","person_external_id":{"person_id":-987655032,"source_id":-987655031,"record_key":"5a-R1"}}','legacy_match');

    SELECT evidence INTO v_ev FROM private.source_persona_identity WHERE source_persona_id=v_ps[1];
    IF v_ev->>'basis'<>'web_detail' OR v_ev->>'candidate_id'<>v_cand::text OR v_ev->>'run_id'<>v_old_run::text
       OR (v_ev->>'candidate_rank')::int<>1 THEN
      RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: kandidatspor mangler i evidensen (%)',v_ev;
    END IF;
    SELECT evidence INTO v_ev FROM private.source_persona_identity WHERE source_persona_id=v_ps[4];
    IF v_ev->>'reason'<>'new_person_needed' OR v_ev->>'basis'<>'human_sheet' OR (v_ev->>'line')::int<>7
       OR (SELECT decision_status FROM private.source_persona_identity WHERE source_persona_id=v_ps[4])<>'unresolved' THEN
      RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: new_person_needed forkert skrevet (%)',v_ev;
    END IF;
    -- Indholds-id (#151, spec §3, §5.2): hændelsens id afledes af (persona, version); kollision fejler lukket.
    IF (SELECT count(*) FROM private.source_persona_identity_event e WHERE e.source_persona_id=ANY(v_ps[1:4]) AND e.version=1
          AND e.id=private.content_uuid('identity-event',jsonb_build_object('source_persona_id',e.source_persona_id,'version',1)))<>4 THEN
      RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: hændelses-id ikke af indholdet';
    END IF;
    BEGIN
      SELECT coalesce(max(version),0) INTO v_i FROM private.source_persona_identity WHERE source_persona_id=v_ps[5];
      INSERT INTO private.source_persona_identity_event(id,source_persona_id,canonical_person_id,decision_status,version,evidence,
        decided_by,decided_by_name,decided_at)
        VALUES (private.content_uuid('identity-event',jsonb_build_object('source_persona_id',v_ps[5],'version',v_i+1)),
                v_ps[7],-987655031,'accepted',1,'{"fixture":"kollision"}',v_actor,'fixture',clock_timestamp());
      SET LOCAL ROLE authenticated;
      PERFORM red_afgoer_source_persona(v_ps[5],v_i,'unresolved',NULL,'kollision','{}');
      RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: hændelseskollision godtaget';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM NOT LIKE 'DETERMINISTIC_ID_COLLISION: identity-event%' THEN RAISE; END IF;
    END;
    RAISE EXCEPTION 'ROLLBACK_5A_DECISION';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='ROLLBACK_5A_DECISION' THEN
      RAISE NOTICE 'OK: fire udgange, kandidatspor, aktualitet, arkbasis og guard pr. oprindelse (kvittering, 1:1-kobling); kernen utilgængelig for klienter';
    ELSE RAISE; END IF;
  END;
END $identity_decision$;

-- Afgørelsen tager den delte kildelås: holder en anden forbindelse den eksklusivt, venter afgørelsen.
DO $identity_decision_lock$
DECLARE
  v_actor uuid := '11000000-0000-0000-0000-000000005a08';
  v_run uuid := '22000000-0000-0000-0000-000000005a08';
  v_persona uuid := '88000000-0000-0000-0000-000000005a81';
  v_conn text := format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),split_part(current_setting('unix_socket_directories'),',',1));
  v_state text;
BEGIN
  PERFORM dblink_connect('decide_lock',v_conn);
  PERFORM dblink_exec('decide_lock','BEGIN');
  PERFORM * FROM dblink('decide_lock','SELECT pg_advisory_xact_lock(hashtextextended(''daa-identity-candidates:-987655081'',0))::text') AS t(x text);
  BEGIN
    INSERT INTO auth.users(id,email) VALUES (v_actor,'5a-dlock@test.invalid');
    INSERT INTO profiles(id,rolle,navn,email) VALUES (v_actor,'redaktion','5a dlock','5a-dlock@test.invalid');
    INSERT INTO source(id,titel,import_key) VALUES (-987655081,'5a L','verify:5a:l');
    INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
      VALUES (v_run,-987655081,'5a-run-l','1.0','verify','verify',repeat('9',64),'{}');
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES (v_persona,-987655081,'5a-l1',v_run);
    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    SET LOCAL ROLE authenticated;
    SET LOCAL lock_timeout='300ms';
    BEGIN
      PERFORM red_afgoer_source_persona(v_persona,0,'different',NULL,'lås','{}');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
    END;
    RESET ROLE;
    RAISE EXCEPTION 'ROLLBACK_5A_DECISION_LOCK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_5A_DECISION_LOCK' THEN
      PERFORM dblink_exec('decide_lock','ROLLBACK'); PERFORM dblink_disconnect('decide_lock'); RAISE;
    END IF;
  END;
  PERFORM dblink_exec('decide_lock','ROLLBACK'); PERFORM dblink_disconnect('decide_lock');
  IF v_state IS DISTINCT FROM '55P03' THEN
    RAISE EXCEPTION 'IDENTITY_DECISION_TEST_FAILED: afgørelsen ventede ikke på kildelåsen (%)',v_state;
  END IF;
  RAISE NOTICE 'OK: afgørelsen tager kildelåsen';
END $identity_decision_lock$;
