-- Trin 6a Task 1: helpost-reglen (private.record_helpost_status / record_helpost_observation).
-- Alt syntetisk. Filen kører i én transaktion og ruller altid tilbage.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.expect_error(p_sql text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE p_token||'%' THEN
      RAISE EXCEPTION 'HELPOST_TEST_WRONG_ERROR: expected % got %', p_token, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'HELPOST_TEST_NO_ERROR: expected %', p_token;
END $$;

-- Hjælper: opretter en forekomst med én top-observation og en accepteret anker-event.
CREATE FUNCTION pg_temp.mk_occ(p_record uuid, p_rend uuid, p_run uuid, p_key text, p_from int, p_to int, p_kind text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_occ uuid; v_obs uuid;
BEGIN
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  VALUES(p_rend,p_key,1,1,p_from,p_to,repeat('x',p_to-p_from),repeat('3',64),repeat('4',64),p_run) RETURNING id INTO v_occ;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id)
  VALUES(v_occ,p_kind,1,1,p_from,p_to,repeat('x',p_to-p_from),'clear','fixture',p_run) RETURNING id INTO v_obs;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
  VALUES(v_occ,p_record,'accepted','{"fixture":true}'::jsonb,1,gen_random_uuid(),'fixture');
  RETURN v_obs;
END $$;

DO $helpost$
DECLARE
  v_source bigint := -6101; v_run uuid := gen_random_uuid(); v_rend uuid; v_rend2 uuid;
  v_rec uuid; v_obs uuid; r record; v_msg text;
BEGIN
  INSERT INTO public.source(id,slags,titel,udgave,aar) VALUES(v_source,'DAA-udgave','Helpost fixture','synthetic',1900);
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES(v_run,v_source,'helpost-'||v_run::text,'fixture','fixture','fixture',repeat('1',64),'{}');
  INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata)
  VALUES(v_source,'hp-r1','pdf_text_layer',repeat('2',64),'{}') RETURNING id INTO v_rend;
  INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata)
  VALUES(v_source,'hp-r2','pdf_text_layer',repeat('5',64),'{}') RETURNING id INTO v_rend2;

  -- (a) ét anker, top-observation person -> ok
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id) VALUES(v_source,'a','person',v_run) RETURNING id INTO v_rec;
  v_obs := pg_temp.mk_occ(v_rec,v_rend,v_run,'a1',100,500,'person');
  SELECT * INTO r FROM private.record_helpost_status(v_rec,'person');
  IF r.status<>'ok' OR r.observation_id<>v_obs THEN RAISE EXCEPTION 'HELPOST_TEST_A: %', r.status; END IF;
  IF private.record_helpost_observation(v_rec,'person')<>v_obs THEN RAISE EXCEPTION 'HELPOST_TEST_A_OBS'; END IF;

  -- (b) helpost + to underforekomster indeni -> ok med helpostens id
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id) VALUES(v_source,'b','person',v_run) RETURNING id INTO v_rec;
  v_obs := pg_temp.mk_occ(v_rec,v_rend,v_run,'b1',100,500,'person');
  PERFORM pg_temp.mk_occ(v_rec,v_rend,v_run,'b2',120,200,'fact');
  PERFORM pg_temp.mk_occ(v_rec,v_rend,v_run,'b3',300,450,'marriage');
  SELECT * INTO r FROM private.record_helpost_status(v_rec,'person');
  IF r.status<>'ok' OR r.observation_id<>v_obs THEN RAISE EXCEPTION 'HELPOST_TEST_B: %', r.status; END IF;
  IF private.record_helpost_observation(v_rec,'person')<>v_obs THEN RAISE EXCEPTION 'HELPOST_TEST_B_OBS'; END IF;

  -- (c) underforekomst stikker ud -> outside
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id) VALUES(v_source,'c','person',v_run) RETURNING id INTO v_rec;
  PERFORM pg_temp.mk_occ(v_rec,v_rend,v_run,'c1',100,500,'person');
  PERFORM pg_temp.mk_occ(v_rec,v_rend,v_run,'c2',120,200,'fact');
  PERFORM pg_temp.mk_occ(v_rec,v_rend,v_run,'c3',480,520,'fact');
  SELECT * INTO r FROM private.record_helpost_status(v_rec,'person');
  IF r.status<>'outside' THEN RAISE EXCEPTION 'HELPOST_TEST_C: %', r.status; END IF;
  PERFORM pg_temp.expect_error(format('SELECT private.record_helpost_observation(%L,''person'')',v_rec),'RECORD_HELPOST_SUBOCCURRENCE_OUTSIDE');

  -- (d) to accepterede person-forekomster -> ambiguous
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id) VALUES(v_source,'d','person',v_run) RETURNING id INTO v_rec;
  PERFORM pg_temp.mk_occ(v_rec,v_rend,v_run,'d1',100,500,'person');
  PERFORM pg_temp.mk_occ(v_rec,v_rend,v_run,'d2',600,900,'person');
  SELECT * INTO r FROM private.record_helpost_status(v_rec,'person');
  IF r.status<>'ambiguous' OR r.observation_id IS NOT NULL THEN RAISE EXCEPTION 'HELPOST_TEST_D: %', r.status; END IF;
  PERFORM pg_temp.expect_error(format('SELECT private.record_helpost_observation(%L,''person'')',v_rec),'RECORD_HELPOST_AMBIGUOUS');

  -- (e) kun structural_context -> none
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id) VALUES(v_source,'e','person',v_run) RETURNING id INTO v_rec;
  PERFORM pg_temp.mk_occ(v_rec,v_rend,v_run,'e1',100,500,'structural_context');
  SELECT * INTO r FROM private.record_helpost_status(v_rec,'person');
  IF r.status<>'none' OR r.observation_id IS NOT NULL THEN RAISE EXCEPTION 'HELPOST_TEST_E: %', r.status; END IF;
  PERFORM pg_temp.expect_error(format('SELECT private.record_helpost_observation(%L,''person'')',v_rec),'RECORD_HELPOST_AMBIGUOUS');

  -- 2018-20-lignende: person_post. Kind person_post -> ok, kind person -> none.
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id) VALUES(v_source,'g','person',v_run) RETURNING id INTO v_rec;
  v_obs := pg_temp.mk_occ(v_rec,v_rend,v_run,'g1',100,500,'person_post');
  SELECT * INTO r FROM private.record_helpost_status(v_rec,'person_post');
  IF r.status<>'ok' OR r.observation_id<>v_obs THEN RAISE EXCEPTION 'HELPOST_TEST_G_OK: %', r.status; END IF;
  SELECT * INTO r FROM private.record_helpost_status(v_rec,'person');
  IF r.status<>'none' THEN RAISE EXCEPTION 'HELPOST_TEST_G_NONE: %', r.status; END IF;

  -- (f) underforekomst i en ANDEN rendition med offsets inde i helpostens -> outside
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id) VALUES(v_source,'f','person',v_run) RETURNING id INTO v_rec;
  PERFORM pg_temp.mk_occ(v_rec,v_rend,v_run,'f1',100,500,'person');
  PERFORM pg_temp.mk_occ(v_rec,v_rend2,v_run,'f2',120,200,'fact');
  SELECT * INTO r FROM private.record_helpost_status(v_rec,'person');
  IF r.status<>'outside' THEN RAISE EXCEPTION 'HELPOST_TEST_F: %', r.status; END IF;

  -- Rettigheder: kun ejeren; ingen API-roller.
  IF has_function_privilege('anon','private.record_helpost_status(uuid,text)','EXECUTE')
     OR has_function_privilege('authenticated','private.record_helpost_observation(uuid,text)','EXECUTE')
     OR has_function_privilege('service_role','private.record_helpost_status(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'HELPOST_TEST_PRIVILEGES';
  END IF;
  RAISE NOTICE 'helpost OK';
END $helpost$;

ROLLBACK;
