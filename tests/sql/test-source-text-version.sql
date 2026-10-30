-- Trin 6a, Task 3: tekstversioner af helposten, klausulsæt bundet til version, helpost_text_current.
-- Alt syntetisk; én transaktion, rulles tilbage.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.expect_error(p_sql text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM IS NULL OR SQLERRM NOT LIKE p_token||'%' THEN
      RAISE EXCEPTION 'TEXT_VERSION_TEST_WRONG_ERROR: expected % got %', p_token, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'TEXT_VERSION_TEST_NO_ERROR: expected %', p_token;
END $$;

-- Basistekst med rå dobbeltmellemrum (50 tegn) og en foldet version af samme spænd (48 tegn).
CREATE FUNCTION pg_temp.fixture(p_key text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_source bigint := -148933; v_run uuid := gen_random_uuid(); v_rend uuid; v_occ uuid; v_parent uuid;
  v_text text := 'Alfa  Bravo, f. 1801 i  Charlie. Død 1860 i Delta.';
  v_rev  text := 'Alfa Bravo, f. 1801 i Charlie. Død 1860 i Delta.';
BEGIN
  INSERT INTO public.source(id,slags,titel,udgave,aar) VALUES(v_source,'DAA-udgave','Text version fixture','synthetic',1900) ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES(v_run,v_source,'text-version-'||v_run::text,'fixture','fixture','fixture',repeat('1',64),'{}');
  INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata)
  VALUES(v_source,'text-version-r-'||v_run::text,'pdf_text_layer',repeat('2',64),'{}') RETURNING id INTO v_rend;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  VALUES(v_rend,'occ-'||p_key,10,10,100,100+char_length(v_text),v_text,repeat('3',64),repeat('4',64),v_run) RETURNING id INTO v_occ;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id)
  VALUES(v_occ,'person_post',10,10,100,100+char_length(v_text),v_text,'clear','fixture',v_run) RETURNING id INTO v_parent;
  RETURN jsonb_build_object('source',v_source,'run',v_run,'rend',v_rend,'occ',v_occ,'parent',v_parent,'text',v_text,'rev',v_rev);
END $$;

CREATE FUNCTION pg_temp.add_version(fx jsonb, p_version integer, p_supersedes uuid, p_preferred boolean, p_text text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO private.source_observation_text(observation_id,rendition_id,version,verbatim_text,char_from,char_to,is_preferred,supersedes_id,extraction_run_id,method,evidence)
  VALUES((fx->>'parent')::uuid,(fx->>'rend')::uuid,p_version,p_text,100,150,p_preferred,p_supersedes,(fx->>'run')::uuid,'fixture','{"basis":"test"}')
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- SQL for én klausul [a,b) af en given tekst, evt. bundet til tekstversion.
CREATE FUNCTION pg_temp.clause_sql(fx jsonb, p_src text, p_seq integer, p_ordinal integer, p_a integer, p_b integer,
                                   p_text_id uuid, p_parent uuid DEFAULT NULL) RETURNS text LANGUAGE sql AS $$
  SELECT format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,
         parent_observation_id,post_char_from,post_char_to,clause_ordinal,clause_classification,clause_flags,clause_set_seq,parent_text_id)
       VALUES(%L,'clause',10,10,%s,%s,%L,'clear','clause_segment_v1',%L,%L,%s,%s,%s,'record_text','[]',%s,%L)$q$,
    fx->>'occ', 100+p_a, 100+p_b, substr(p_src, p_a+1, p_b-p_a), fx->>'run', coalesce(p_parent::text, fx->>'parent'),
    p_a, p_b, p_ordinal, p_seq, p_text_id)
$$;

-- test_clause_on_text_version_validates_against_version
DO $$
DECLARE fx jsonb := pg_temp.fixture('a'); v_t uuid; v_t2 uuid;
BEGIN
  v_t := pg_temp.add_version(fx,1,NULL,true,fx->>'rev');
  -- [0,30) af versionens tekst: accepteres bundet til versionen
  EXECUTE pg_temp.clause_sql(fx, fx->>'rev', 1, 1, 0, 30, v_t);
  -- samme klausul uden parent_text_id: basisteksten har dobbeltmellemrum, så teksten afviger
  PERFORM pg_temp.expect_error(pg_temp.clause_sql(fx, fx->>'rev', 2, 1, 0, 30, NULL), 'EVIDENCE_CLAUSE_TEXT_MISMATCH');
  -- bundet til en anden version med anden ordlyd: afvises
  v_t2 := pg_temp.add_version(fx,2,v_t,false,'Xxxx Bravo, f. 1801 i Charlie. Død 1860 i Delta.');
  PERFORM pg_temp.expect_error(pg_temp.clause_sql(fx, fx->>'rev', 2, 1, 0, 30, v_t2), 'EVIDENCE_CLAUSE_TEXT_MISMATCH');
  -- grænsen post_char_to følger versionens længde (48), ikke basisteksten (50)
  PERFORM pg_temp.expect_error(pg_temp.clause_sql(fx, fx->>'text', 2, 1, 31, 50, v_t), 'EVIDENCE_CLAUSE_POST_SPAN_OUTSIDE_PARENT');
  -- et sæt uden binding skæres stadig af basisteksten
  EXECUTE pg_temp.clause_sql(fx, fx->>'text', 2, 1, 0, 4, NULL);
END $$;

-- test_text_version_of_other_observation_rejected
DO $$
DECLARE fx1 jsonb := pg_temp.fixture('b1'); fx2 jsonb := pg_temp.fixture('b2'); v_t2 uuid;
BEGIN
  v_t2 := pg_temp.add_version(fx2,1,NULL,true,fx2->>'rev');
  PERFORM pg_temp.expect_error(pg_temp.clause_sql(fx1, fx2->>'rev', 1, 1, 0, 30, v_t2), 'EVIDENCE_CLAUSE_PARENT_TEXT_INVALID');
  PERFORM pg_temp.expect_error(pg_temp.clause_sql(fx1, fx1->>'text', 1, 1, 0, 30, gen_random_uuid()), 'EVIDENCE_CLAUSE_PARENT_TEXT_INVALID');
END $$;

-- test_mixed_text_in_set_rejected
DO $$
DECLARE fx jsonb := pg_temp.fixture('c'); v_t uuid;
BEGIN
  v_t := pg_temp.add_version(fx,1,NULL,true,fx->>'rev');
  EXECUTE pg_temp.clause_sql(fx, fx->>'rev', 1, 1, 0, 30, v_t);
  PERFORM pg_temp.expect_error(pg_temp.clause_sql(fx, fx->>'text', 1, 2, 31, 50, NULL), 'EVIDENCE_CLAUSE_SET_TEXT_MIXED');
  -- samme binding i samme sæt er fint
  EXECUTE pg_temp.clause_sql(fx, fx->>'rev', 1, 2, 31, 48, v_t);
END $$;

-- parent_text_id kun på klausuler
DO $$
DECLARE fx jsonb := pg_temp.fixture('d'); v_t uuid;
BEGIN
  v_t := pg_temp.add_version(fx,1,NULL,true,fx->>'rev');
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_text_id)
       VALUES(%L,'person_post',10,10,100,110,'Alfa Bravo','clear','fixture',%L,%L)$q$, fx->>'occ', fx->>'run', v_t),
    'EVIDENCE_CLAUSE_PARENT_FORBIDDEN');
END $$;

-- test_helpost_text_current
DO $$
DECLARE fx jsonb := pg_temp.fixture('e'); v_t1 uuid; v_t2 uuid; r record;
BEGIN
  SELECT * INTO r FROM private.helpost_text_current((fx->>'parent')::uuid);
  IF r.text_id IS NOT NULL OR r.verbatim_text<>fx->>'text' THEN RAISE EXCEPTION 'TEXT_VERSION_TEST: basistekst forventet'; END IF;
  v_t1 := pg_temp.add_version(fx,1,NULL,true,fx->>'rev');
  SELECT * INTO r FROM private.helpost_text_current((fx->>'parent')::uuid);
  IF r.text_id IS DISTINCT FROM v_t1 OR r.verbatim_text<>fx->>'rev' THEN RAISE EXCEPTION 'TEXT_VERSION_TEST: foretrukken version forventet'; END IF;
  -- højere version, ikke foretrukken: den foretrukne vinder stadig
  v_t2 := pg_temp.add_version(fx,2,v_t1,false,'Anden version af teksten.');
  SELECT * INTO r FROM private.helpost_text_current((fx->>'parent')::uuid);
  IF r.text_id IS DISTINCT FROM v_t1 THEN RAISE EXCEPTION 'TEXT_VERSION_TEST: is_preferred skal vinde over højere version'; END IF;
  IF (SELECT count(*) FROM private.helpost_text_current((fx->>'parent')::uuid))<>1 THEN
    RAISE EXCEPTION 'TEXT_VERSION_TEST: præcis én række forventet'; END IF;
  IF has_function_privilege('anon','private.helpost_text_current(uuid)','EXECUTE')
     OR has_function_privilege('authenticated','private.helpost_text_current(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'TEXT_VERSION_TEST: helpost_text_current skal være revoked';
  END IF;
END $$;

ROLLBACK;
\echo PASS test-source-text-version
