-- #148 4.1c: clause_evidence — autorisationsform, writer, dispositioner, replay, regression.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.expect_error(p_sql text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE p_token||'%' THEN RAISE EXCEPTION 'CLAUSE_WRITER_TEST_WRONG_ERROR: expected % got %', p_token, SQLERRM; END IF; RETURN; END;
  RAISE EXCEPTION 'CLAUSE_WRITER_TEST_NO_ERROR: expected %', p_token;
END $$;

-- Fixture: 149a-lignende source_evidence-batch for én record med kendt tekst.
CREATE FUNCTION pg_temp.se_fixture(p_key text, p_text text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_source bigint := 148100 + abs(hashtext(p_key)) % 100000; v_profile text := 'fixture-se-'||p_key; v_sha text; v_config jsonb; v_actor uuid;
  v_msha text := encode(extensions.digest('manifest-se:'||p_key,'sha256'),'hex'); v_psha text := encode(extensions.digest('preview-se:'||p_key,'sha256'),'hex');
  v_auth uuid; v_batch uuid; v_payload jsonb;
BEGIN
  INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES(v_source,'Fixture '||p_key,'synthetic','1900','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  v_config:=jsonb_build_object('citation_label_template','Synthetic side {page_from}','extractor_version','fixture-v1',
    'observation_extraction_method','deterministic_segment_v1','rendition_key','fixture-r1','rendition_kind','pdf_text_layer',
    'rendition_metadata',jsonb_build_object('edition','fixture','pdf_sha256',repeat('a',64),'pdftotext_version','fixture 0.0'),
    'run_key_prefix','reimport-source-evidence:','schema_version','source-evidence-manifest-v1');
  v_sha:=private.reimport_canonical_json_sha256(v_config);
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES(v_source,v_profile,'source-evidence-v1',v_sha,v_config) ON CONFLICT DO NOTHING;
  SELECT id INTO v_actor FROM public.profiles WHERE rolle='redaktion' ORDER BY id LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  v_payload:=jsonb_build_object('source_record_key',p_key,'source_id',v_source,'category','person_post','disposition','retain_source_only',
    'rendition_content_sha256',repeat('c',64),'source_span',jsonb_build_object('char_from',100,'char_to',100+char_length(p_text)),
    'page_evidence',jsonb_build_object('page_from',10,'page_to',10),'verbatim_text',p_text,
    'verbatim_sha256',encode(extensions.digest(p_text,'sha256'),'hex'),'anchor_method','deterministic-segment','segment_version','fixture');
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(v_msha,v_psha,jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    v_source,v_profile,v_sha,'{"person_creates":0,"source_evidence":1}'::jsonb,jsonb_build_object('source-evidence:'||p_key,v_payload),gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch:=public.red_begin_reimport(v_auth,v_msha,v_psha);
  PERFORM public.red_apply_reimport_source_evidence(v_batch,'source-evidence:'||p_key,v_payload);
  PERFORM public.red_finalize_reimport(v_batch);
  RESET role;
  RETURN jsonb_build_object('source_id',v_source,'actor',v_actor,'record_key',p_key,'text',p_text,
    'parent_sha256',encode(extensions.digest(p_text,'sha256'),'hex'));
END $$;

-- Klausul-payload for teksten 'Alfa Bravo, f. 1801, d. 1860. Gift 1830 m. Charlie Delta.' (to klausuler, ét mellemrum).
CREATE FUNCTION pg_temp.ce_payload(p_fx jsonb, p_clauses jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('source_record_key',p_fx->>'record_key','rendition_content_sha256',repeat('c',64),
    'parent_verbatim_sha256',p_fx->>'parent_sha256','clause_rules_version','clause-rules-fixture-v1','segmenter_version','clause_segment.py@v1',
    'ledger_sha256',repeat('d',64),'gap_charset',jsonb_build_array(' '),'clauses',p_clauses)
$$;
-- Datadrevet: klausul 1 = til og med punktummet før ' Gift' (1-baseret position p), klausul 2 fra p+1 (0-baseret).
CREATE FUNCTION pg_temp.ce_clauses(p_text text) RETURNS jsonb LANGUAGE sql AS $$
  WITH s AS (SELECT position('. Gift' in p_text) AS p)
  SELECT jsonb_build_array(
    jsonb_build_object('ordinal',1,'char_from',0,'char_to',s.p,'classification','record_text','flags','[]'::jsonb,'verbatim_sha256',encode(extensions.digest(substr(p_text,1,s.p),'sha256'),'hex')),
    jsonb_build_object('ordinal',2,'char_from',s.p+1,'char_to',char_length(p_text),'classification','record_text','flags','["uncertain_marker"]'::jsonb,'verbatim_sha256',encode(extensions.digest(substr(p_text,s.p+2),'sha256'),'hex')))
  FROM s
$$;

-- Kør én clause_evidence-batch med ét element og vilkårlig payload.
CREATE FUNCTION pg_temp.ce_apply(p_fx jsonb, p_payload jsonb, p_element_key text, p_nonce text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_profile text := 'fixture-ce-'||(p_fx->>'record_key'); v_config jsonb; v_sha text; v_auth uuid; v_batch uuid; v_result jsonb;
  v_msha text := encode(extensions.digest(p_nonce,'sha256'),'hex');
BEGIN
  v_config:=jsonb_build_object('citation_label_template','Synthetic side {page_from}','extractor_version','clause-evidence-v1',
    'observation_extraction_method','clause_segment_v1','rendition_key','fixture-r1','rendition_kind','pdf_text_layer',
    'rendition_metadata',jsonb_build_object('edition','fixture','pdf_sha256',repeat('a',64),'pdftotext_version','fixture 0.0'),
    'run_key_prefix','reimport-clause-evidence:','schema_version','clause-evidence-manifest-v1');
  v_sha:=private.reimport_canonical_json_sha256(v_config);
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES((p_fx->>'source_id')::bigint,v_profile,'clause-evidence-v1',v_sha,v_config) ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub',p_fx->>'actor',true);
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(v_msha,repeat('9',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    (p_fx->>'source_id')::bigint,v_profile,v_sha,'{"person_creates":0,"source_evidence":0,"clause_evidence":1}'::jsonb,
    jsonb_build_object('clause-evidence:'||p_element_key,p_payload),gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch:=public.red_begin_reimport(v_auth,v_msha,repeat('9',64));
  v_result:=public.red_apply_reimport_clause_evidence(v_batch,'clause-evidence:'||p_element_key,p_payload);
  PERFORM public.red_finalize_reimport(v_batch);
  RESET role;
  RETURN v_result||jsonb_build_object('batch_id',v_batch,'authorization_id',v_auth,'manifest_sha256',v_msha);
END $$;

DO $t1_authorization_forms$
BEGIN
  -- Regression (spec fund 8): 149a og 149b's former valideres uændret.
  PERFORM private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":1}'::jsonb, jsonb_build_object('source-evidence:k','{}'::jsonb));
  PERFORM private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"legacy_migrations":1}'::jsonb, jsonb_build_object('legacy-migration:k','{}'::jsonb));
  -- Ny form.
  PERFORM private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"clause_evidence":2}'::jsonb, jsonb_build_object('clause-evidence:a','{}'::jsonb,'clause-evidence:b','{}'::jsonb));
  -- Ukendt nøgle og præfiks afvises fortsat.
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"noget_andet":1}'::jsonb, jsonb_build_object('noget-andet:a','{}'::jsonb))$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"clause_evidence":1}'::jsonb, jsonb_build_object('source-evidence:a','{}'::jsonb))$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  RAISE NOTICE 't1 authorization forms OK';
END $t1_authorization_forms$;

DO $t2_happy_path_and_replay$
DECLARE fx jsonb; r jsonb; v_text text := 'Alfa Bravo, f. 1801, d. 1860. Gift 1830 m. Charlie Delta.'; v_n integer; v_disp text[]; v_auth uuid; v_batch uuid; v_res jsonb;
BEGIN
  fx := pg_temp.se_fixture('CE1', v_text);
  r := pg_temp.ce_apply(fx, pg_temp.ce_payload(fx, pg_temp.ce_clauses(v_text)), 'CE1', 'ce1-nonce');
  IF (r->>'clauses')::int<>2 THEN RAISE EXCEPTION 'T2_CLAUSE_COUNT: %', r; END IF;
  SELECT count(*) INTO v_n FROM private.source_observation ob JOIN private.source_record_occurrence o ON o.id=ob.occurrence_id JOIN private.source_rendition rd ON rd.id=o.rendition_id
   WHERE rd.source_id=(fx->>'source_id')::bigint AND ob.observation_kind='clause';
  IF v_n<>2 THEN RAISE EXCEPTION 'T2_CLAUSE_ROWS: %', v_n; END IF;
  -- Absolutte offsets: helposten starter ved 100; klausul 1 slutter ved første '. '-punktum.
  IF NOT EXISTS (SELECT 1 FROM private.source_observation WHERE observation_kind='clause' AND clause_ordinal=1 AND char_from=100 AND char_to=100+position('. Gift' in v_text) AND page_from=10 AND page_to=10) THEN RAISE EXCEPTION 'T2_ABSOLUTE_OFFSETS'; END IF;
  SELECT array_agg(d.disposition ORDER BY ob.clause_ordinal) INTO v_disp FROM private.clause_disposition_current d JOIN private.source_observation ob ON ob.id=d.observation_id WHERE ob.observation_kind='clause' AND ob.extraction_run_id IN (SELECT id FROM private.extraction_run WHERE source_id=(fx->>'source_id')::bigint AND run_key LIKE 'reimport-clause-evidence:%');
  IF v_disp<>ARRAY['afventer_fortolkning','maskinelt_flagget'] THEN RAISE EXCEPTION 'T2_DISPOSITIONS: %', v_disp; END IF;
  IF (SELECT count(*) FROM private.reimport_event WHERE batch_id=(r->>'batch_id')::uuid AND operation='clause_evidence')<>1 THEN RAISE EXCEPTION 'T2_EVENT_MISSING'; END IF;
  IF (SELECT observed_counts FROM private.reimport_batch WHERE id=(r->>'batch_id')::uuid)<>'{"person_creates":0,"source_evidence":0,"clause_evidence":1}'::jsonb THEN RAISE EXCEPTION 'T2_OBSERVED_COUNTS'; END IF;
  -- Replay: samme manifest/preview/profil → already_applied (samme batch-id fra red_begin_reimport).
  PERFORM set_config('request.jwt.claim.sub',fx->>'actor',true); PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(r->>'manifest_sha256',repeat('9',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    (fx->>'source_id')::bigint,'fixture-ce-CE1',(SELECT profile_sha256 FROM private.reimport_writer_profile WHERE source_id=(fx->>'source_id')::bigint AND profile_id='fixture-ce-CE1'),
    '{"person_creates":0,"source_evidence":0,"clause_evidence":1}'::jsonb,jsonb_build_object('clause-evidence:CE1',pg_temp.ce_payload(fx, pg_temp.ce_clauses(v_text))),gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch:=public.red_begin_reimport(v_auth,r->>'manifest_sha256',repeat('9',64));
  IF v_batch<>(r->>'batch_id')::uuid THEN RAISE EXCEPTION 'T2_REPLAY_NEW_BATCH'; END IF;
  v_res:=public.red_reimport_batch_result(v_auth,v_batch);
  IF v_res->>'status'<>'finalized' THEN RAISE EXCEPTION 'T2_REPLAY_RESULT: %', v_res; END IF;
  RESET role;
  RAISE NOTICE 't2 happy path and replay OK';
END $t2_happy_path_and_replay$;

DO $t3_rejections$
DECLARE fx jsonb; v_text text := 'Echo Foxtrot, f. 1811, d. 1870. Gift 1840 m. Golf Hotel Ida.'; p jsonb; c jsonb;
BEGIN
  fx := pg_temp.se_fixture('CE2', v_text);
  c := pg_temp.ce_clauses(v_text);
  -- Forkert parent-hash (helposten er ændret siden ledgeren blev bygget).
  p := pg_temp.ce_payload(fx, c) || jsonb_build_object('parent_verbatim_sha256',repeat('e',64));
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.ce_apply(%L::jsonb,%L::jsonb,%L,%L)',fx,p,'CE2','n1'),'CLAUSE_EVIDENCE_PARENT_TEXT_DRIFT');
  -- Klausulhash matcher ikke udsnittet.
  p := pg_temp.ce_payload(fx, jsonb_set(c,'{0,verbatim_sha256}',to_jsonb(repeat('f',64))));
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.ce_apply(%L::jsonb,%L::jsonb,%L,%L)',fx,p,'CE2','n2'),'CLAUSE_EVIDENCE_TEXT_HASH_MISMATCH');
  -- Mellemrum indeholder ikke-hvidlistet tegn: skub klausul 2 ét tegn frem, så første bogstav efter mellemrummet bliver "gap".
  p := pg_temp.ce_payload(fx, jsonb_set(jsonb_set(c,'{1,char_from}',to_jsonb(position('. Gift' in v_text)+2)),'{1,verbatim_sha256}',to_jsonb(encode(extensions.digest(substr(v_text,position('. Gift' in v_text)+3),'sha256'),'hex'))));
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.ce_apply(%L::jsonb,%L::jsonb,%L,%L)',fx,p,'CE2','n3'),'CLAUSE_EVIDENCE_GAP_INVALID');
  -- Ordinal-hul.
  p := pg_temp.ce_payload(fx, jsonb_set(c,'{1,ordinal}','3'));
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.ce_apply(%L::jsonb,%L::jsonb,%L,%L)',fx,p,'CE2','n4'),'CLAUSE_EVIDENCE_ORDINAL_INVALID');
  -- Manglende nøgle i payload.
  p := pg_temp.ce_payload(fx, c) - 'gap_charset';
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.ce_apply(%L::jsonb,%L::jsonb,%L,%L)',fx,p,'CE2','n5'),'REIMPORT_WRITER_CLAUSE_EVIDENCE_INVALID');
  -- Element-id ≠ clause-evidence:<record_key>.
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.ce_apply(%L::jsonb,%L::jsonb,%L,%L)',fx,pg_temp.ce_payload(fx,c),'ANDEN','n6'),'REIMPORT_WRITER_CLAUSE_EVIDENCE_INVALID');
  -- Gyldig apply, derefter dublet under samme helpost afvises.
  PERFORM pg_temp.ce_apply(fx, pg_temp.ce_payload(fx, c), 'CE2', 'n7');
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.ce_apply(%L::jsonb,%L::jsonb,%L,%L)',fx,pg_temp.ce_payload(fx,c),'CE2','n8'),'REIMPORT_WRITER_CLAUSE_EVIDENCE_EXISTS');
  RAISE NOTICE 't3 rejections OK';
END $t3_rejections$;

DO $t4_acl$
BEGIN
  IF NOT has_function_privilege('authenticated','public.red_apply_reimport_clause_evidence(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.red_apply_reimport_clause_evidence(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.write_clause_evidence(uuid,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'T4_ACL_INVALID';
  END IF;
  RAISE NOTICE 't4 acl OK';
END $t4_acl$;

ROLLBACK;
