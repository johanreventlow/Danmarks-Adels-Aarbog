-- Omsegmentering (spec 2026-09-27, Task 2): clause_revision — autorisationsform, writer,
-- afvisninger, fortrydelse, batch-resultat. Kræver kontrakt v2 (reimport-writer-v2-bootstrap.sql)
-- som klausul-writer-testen. Alt syntetisk; én transaktion, rulles tilbage.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.expect_error(p_sql text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN
    IF SQLERRM IS NULL OR SQLERRM NOT LIKE p_token||'%' THEN RAISE EXCEPTION 'CLAUSE_REVISION_TEST_WRONG_ERROR: expected % got %', p_token, SQLERRM; END IF; RETURN; END;
  RAISE EXCEPTION 'CLAUSE_REVISION_TEST_NO_ERROR: expected %', p_token;
END $$;

-- Fixture-funktionerne er kopieret fra test-clause-evidence-writer.sql (se_fixture, ce_payload,
-- ce_clauses, ce_apply), så sæt 1 skrives ad den rigtige writer-vej.
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
    'ledger_sha256',repeat('d',64),'rendition_projection_sha256',repeat('e',64),'gap_charset',jsonb_build_array(' '),'clauses',p_clauses)
$$;
-- Datadrevet: klausul 1 = til og med punktummet før ' Gift' (1-baseret position p), klausul 2 fra p+1 (0-baseret).
CREATE FUNCTION pg_temp.ce_clauses(p_text text) RETURNS jsonb LANGUAGE sql AS $$
  WITH s AS (SELECT position('. Gift' in p_text) AS p)
  SELECT jsonb_build_array(
    jsonb_build_object('ordinal',1,'char_from',0,'char_to',s.p,'rendition_char_from',100,'rendition_char_to',100+s.p,'classification','record_text','flags','[]'::jsonb,'verbatim_sha256',encode(extensions.digest(substr(p_text,1,s.p),'sha256'),'hex')),
    jsonb_build_object('ordinal',2,'char_from',s.p+1,'char_to',char_length(p_text),'rendition_char_from',100+s.p+1,'rendition_char_to',100+char_length(p_text),'classification','record_text','flags','["uncertain_marker"]'::jsonb,'verbatim_sha256',encode(extensions.digest(substr(p_text,s.p+2),'sha256'),'hex')))
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

-- Revisions-payload: klausuler som clause_evidence + det sæt, den erstatter.
CREATE FUNCTION pg_temp.cr_payload(p_fx jsonb, p_clauses jsonb, p_seq integer, p_sha text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.ce_payload(p_fx,p_clauses)||jsonb_build_object('replaces_clause_set_seq',p_seq,'replaces_clause_set_sha256',p_sha)
$$;
-- Én klausul over hele helposten.
CREATE FUNCTION pg_temp.whole(p_text text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_array(jsonb_build_object('ordinal',1,'char_from',0,'char_to',char_length(p_text),'rendition_char_from',100,'rendition_char_to',100+char_length(p_text),
    'classification','record_text','flags','[]'::jsonb,'verbatim_sha256',encode(extensions.digest(p_text,'sha256'),'hex')))
$$;
CREATE FUNCTION pg_temp.parent_of(p_fx jsonb) RETURNS uuid LANGUAGE sql AS $$
  SELECT ob.id FROM private.source_observation ob JOIN private.source_record_occurrence o ON o.id=ob.occurrence_id
    JOIN private.source_rendition rd ON rd.id=o.rendition_id
   WHERE rd.source_id=(p_fx->>'source_id')::bigint AND ob.parent_observation_id IS NULL AND ob.observation_kind='person_post'
$$;
-- Kør én clause_revision-batch.
CREATE FUNCTION pg_temp.cr_apply(p_fx jsonb, p_payload jsonb, p_nonce text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_profile text := 'fixture-cr-'||(p_fx->>'record_key'); v_config jsonb; v_sha text; v_auth uuid; v_batch uuid; v_result jsonb;
  v_msha text := encode(extensions.digest(p_nonce,'sha256'),'hex'); v_element text := 'clause-revision:'||(p_fx->>'record_key');
BEGIN
  v_config:=jsonb_build_object('citation_label_template','Synthetic side {page_from}','extractor_version','clause-revision-v1',
    'observation_extraction_method','clause_segment_v1','rendition_key','fixture-r1','rendition_kind','pdf_text_layer',
    'rendition_metadata',jsonb_build_object('edition','fixture','pdf_sha256',repeat('a',64),'pdftotext_version','fixture 0.0'),
    'run_key_prefix','reimport-clause-revision:','schema_version','clause-revision-manifest-v1');
  v_sha:=private.reimport_canonical_json_sha256(v_config);
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES((p_fx->>'source_id')::bigint,v_profile,'clause-revision-v1',v_sha,v_config) ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub',p_fx->>'actor',true);
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(v_msha,repeat('8',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    (p_fx->>'source_id')::bigint,v_profile,v_sha,'{"person_creates":0,"source_evidence":0,"clause_revisions":1}'::jsonb,
    jsonb_build_object(v_element,p_payload),gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch:=public.red_begin_reimport(v_auth,v_msha,repeat('8',64));
  v_result:=public.red_apply_reimport_clause_revision(v_batch,v_element,p_payload);
  PERFORM public.red_finalize_reimport(v_batch);
  RESET role;
  RETURN v_result||jsonb_build_object('batch_id',v_batch,'authorization_id',v_auth,'manifest_sha256',v_msha);
END $$;

DO $t1_authorization_forms$
BEGIN
  PERFORM private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"clause_revisions":2}'::jsonb,
    jsonb_build_object('clause-revision:a','{}'::jsonb,'clause-revision:b','{}'::jsonb));
  PERFORM private.validate_reimport_authorization_payload(
    '{"person_creates":0,"source_evidence":0,"legacy_migrations":0,"clause_evidence":0,"interpretation_proposals":0,"clause_revisions":1}'::jsonb,
    jsonb_build_object('clause-revision:a','{}'::jsonb));
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"clause_revisions":1}'::jsonb, jsonb_build_object('clause-evidence:a','{}'::jsonb))$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"clause_evidence":1}'::jsonb, jsonb_build_object('clause-revision:a','{}'::jsonb))$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"clause_revisions":"1"}'::jsonb, jsonb_build_object('clause-revision:a','{}'::jsonb))$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  RAISE NOTICE 't1 authorization forms OK';
END $t1_authorization_forms$;

DO $t2_revision_and_undo$
DECLARE fx jsonb; v_text text := 'Alfa Bravo, f. 1801, d. 1860. Gift 1830 m. Charlie Delta.'; v_parent uuid; h1 text; r jsonb; r2 jsonb; v_disp text[]; v_n integer; v_res jsonb;
BEGIN
  fx := pg_temp.se_fixture('CR1', v_text);
  PERFORM pg_temp.ce_apply(fx, pg_temp.ce_payload(fx, pg_temp.ce_clauses(v_text)), 'CR1', 'cr1-ce');
  v_parent := pg_temp.parent_of(fx);
  h1 := private.clause_set_sha256(v_parent,1);
  -- Revision: to klausuler → én.
  r := pg_temp.cr_apply(fx, pg_temp.cr_payload(fx, pg_temp.whole(v_text), 1, h1), 'cr1-rev1');
  IF (r->>'clauses')::int<>1 OR (r->>'clauses_replaced')::int<>2 OR (r->>'clause_set_seq')::int<>2
     OR r->>'before_clause_set_sha256'<>h1 OR r->>'after_clause_set_sha256'<>private.clause_set_sha256(v_parent,2) THEN
    RAISE EXCEPTION 'T2_RESULT: %', r;
  END IF;
  SELECT count(*) INTO v_n FROM private.clause_observation_current WHERE parent_observation_id=v_parent;
  IF v_n<>1 THEN RAISE EXCEPTION 'T2_CURRENT: %', v_n; END IF;
  SELECT array_agg(d.disposition ORDER BY o.clause_set_seq NULLS FIRST, o.clause_ordinal) INTO v_disp
    FROM private.clause_disposition_current d JOIN private.source_observation o ON o.id=d.observation_id WHERE o.parent_observation_id=v_parent;
  IF v_disp<>ARRAY['erstattet','erstattet','afventer_fortolkning'] THEN RAISE EXCEPTION 'T2_DISPOSITIONS: %', v_disp; END IF;
  IF (SELECT count(*) FROM private.reimport_event WHERE batch_id=(r->>'batch_id')::uuid AND operation='clause_revision'
        AND after_sha256=r->>'after_clause_set_sha256' AND payload->>'before_clause_set_sha256'=h1)<>1 THEN
    RAISE EXCEPTION 'T2_EVENT';
  END IF;
  IF (SELECT observed_counts FROM private.reimport_batch WHERE id=(r->>'batch_id')::uuid)<>'{"person_creates":0,"source_evidence":0,"clause_revisions":1}'::jsonb THEN
    RAISE EXCEPTION 'T2_OBSERVED_COUNTS';
  END IF;
  -- Batch-resultatet kender operationen.
  PERFORM set_config('request.jwt.claim.sub',fx->>'actor',true); PERFORM set_config('role','authenticated',true);
  v_res := public.red_reimport_batch_result((r->>'authorization_id')::uuid,(r->>'batch_id')::uuid);
  RESET role;
  IF v_res->>'status'<>'finalized' THEN RAISE EXCEPTION 'T2_BATCH_RESULT: %', v_res; END IF;
  -- Fortrydelse: en ny revision tilbage til den gamle opdeling (sæt 3 = sæt 1's indhold).
  r2 := pg_temp.cr_apply(fx, pg_temp.cr_payload(fx, pg_temp.ce_clauses(v_text), 2, private.clause_set_sha256(v_parent,2)), 'cr1-rev2');
  IF (r2->>'clause_set_seq')::int<>3 OR private.clause_set_sha256(v_parent,3)<>h1 THEN RAISE EXCEPTION 'T2_UNDO: %', r2; END IF;
  SELECT count(*) INTO v_n FROM private.clause_observation_current WHERE parent_observation_id=v_parent;
  IF v_n<>2 THEN RAISE EXCEPTION 'T2_UNDO_CURRENT: %', v_n; END IF;
  RAISE NOTICE 't2 revision and undo OK';
END $t2_revision_and_undo$;

DO $t3_rejections$
DECLARE fx jsonb; v_text text := 'Echo Foxtrot, f. 1811, d. 1870. Gift 1840 m. Golf Hotel Ida.'; v_parent uuid; h1 text; c jsonb; p jsonb; v_clause uuid; r jsonb;
BEGIN
  fx := pg_temp.se_fixture('CR2', v_text);
  c := pg_temp.ce_clauses(v_text);
  PERFORM pg_temp.ce_apply(fx, pg_temp.ce_payload(fx, c), 'CR2', 'cr2-ce');
  v_parent := pg_temp.parent_of(fx);
  h1 := private.clause_set_sha256(v_parent,1);
  -- Forkert basissæt og forkert basishash.
  p := pg_temp.cr_payload(fx, pg_temp.whole(v_text), 2, h1);
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.cr_apply(%L::jsonb,%L::jsonb,%L)',fx,p,'cr2-n1'),'CLAUSE_REVISION_BASE_DRIFT');
  p := pg_temp.cr_payload(fx, pg_temp.whole(v_text), 1, repeat('0',64));
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.cr_apply(%L::jsonb,%L::jsonb,%L)',fx,p,'cr2-n2'),'CLAUSE_REVISION_BASE_DRIFT');
  -- Uændret sæt ⇒ NOOP.
  p := pg_temp.cr_payload(fx, c, 1, h1);
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.cr_apply(%L::jsonb,%L::jsonb,%L)',fx,p,'cr2-n3'),'CLAUSE_REVISION_NOOP');
  -- Payload uden replaces_* ⇒ INVALID (clause_evidence-formen gælder ikke her).
  p := pg_temp.ce_payload(fx, pg_temp.whole(v_text));
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.cr_apply(%L::jsonb,%L::jsonb,%L)',fx,p,'cr2-n4'),'REIMPORT_WRITER_CLAUSE_REVISION_INVALID');
  -- Menneskelig disposition på det aktuelle sæt ⇒ afvist.
  SELECT id INTO v_clause FROM private.source_observation WHERE parent_observation_id=v_parent AND clause_ordinal=1;
  INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,decided_by,decided_by_name,decided_at,evidence)
  VALUES(v_clause,2,'struktureret','human',(fx->>'actor')::uuid,'Fixture',clock_timestamp(),'{"ark":"fixture"}');
  p := pg_temp.cr_payload(fx, pg_temp.whole(v_text), 1, h1);
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.cr_apply(%L::jsonb,%L::jsonb,%L)',fx,p,'cr2-n5'),'CLAUSE_REVISION_HAS_HUMAN_DISPOSITION');
  RAISE NOTICE 't3 rejections OK';
END $t3_rejections$;

DO $t4_interpretations_and_flags_only$
DECLARE fx jsonb; v_text text := 'Juliet Kilo, f. 1821, d. 1880. Gift 1850 m. Lima Mike.'; v_parent uuid; h1 text; c jsonb; p jsonb; v_clause uuid; r jsonb;
BEGIN
  fx := pg_temp.se_fixture('CR3', v_text);
  c := pg_temp.ce_clauses(v_text);
  PERFORM pg_temp.ce_apply(fx, pg_temp.ce_payload(fx, c), 'CR3', 'cr3-ce');
  v_parent := pg_temp.parent_of(fx);
  h1 := private.clause_set_sha256(v_parent,1);
  -- Kun flag ændret (klausul 2 mister sit flag) er IKKE en no-op.
  p := pg_temp.cr_payload(fx, jsonb_set(c,'{1,flags}','[]'::jsonb), 1, h1);
  r := pg_temp.cr_apply(fx, p, 'cr3-rev1');
  IF (r->>'clause_set_seq')::int<>2 THEN RAISE EXCEPTION 'T4_FLAGS_ONLY: %', r; END IF;
  -- Et fortolkningslink til det aktuelle sæt ⇒ revisionen afvises. Linket indsættes rå
  -- (replica-rollen slår FK'en til fortolkningen fra; rulles tilbage med filen).
  SELECT id INTO v_clause FROM private.source_observation WHERE parent_observation_id=v_parent AND clause_set_seq=2 AND clause_ordinal=1;
  PERFORM set_config('session_replication_role','replica',true);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal) VALUES(gen_random_uuid(),v_clause,'supporting',1);
  PERFORM set_config('session_replication_role','origin',true);
  p := pg_temp.cr_payload(fx, c, 2, private.clause_set_sha256(v_parent,2));
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.cr_apply(%L::jsonb,%L::jsonb,%L)',fx,p,'cr3-n1'),'CLAUSE_REVISION_HAS_INTERPRETATIONS');
  RAISE NOTICE 't4 interpretations and flags-only OK';
END $t4_interpretations_and_flags_only$;

DO $t5_batch_result_stray_event$
DECLARE fx jsonb; v_text text := 'November Oscar, f. 1831. Gift 1860 m. Papa Quebec.'; v_parent uuid; r jsonb; v_err text;
BEGIN
  fx := pg_temp.se_fixture('CR4', v_text);
  PERFORM pg_temp.ce_apply(fx, pg_temp.ce_payload(fx, pg_temp.ce_clauses(v_text)), 'CR4', 'cr4-ce');
  v_parent := pg_temp.parent_of(fx);
  r := pg_temp.cr_apply(fx, pg_temp.cr_payload(fx, pg_temp.whole(v_text), 1, private.clause_set_sha256(v_parent,1)), 'cr4-rev1');
  -- En clause_revision-event uden for autorisationen skal fælde batch-resultatet.
  PERFORM set_config('session_replication_role','replica',true);
  INSERT INTO private.reimport_event(batch_id,element_id,operation,source_record_key,payload,after_sha256)
  VALUES((r->>'batch_id')::uuid,'clause-revision:FREMMED','clause_revision','FREMMED','{}'::jsonb,repeat('1',64));
  PERFORM set_config('session_replication_role','origin',true);
  PERFORM set_config('request.jwt.claim.sub',fx->>'actor',true); PERFORM set_config('role','authenticated',true);
  v_err := NULL;
  BEGIN
    PERFORM public.red_reimport_batch_result((r->>'authorization_id')::uuid,(r->>'batch_id')::uuid);
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  RESET role;
  IF v_err IS NULL OR v_err NOT LIKE 'REIMPORT_WRITER_BATCH_RESULT_INVALID%' THEN
    RAISE EXCEPTION 'T5_STRAY_EVENT_NOT_CAUGHT: %', v_err;
  END IF;
  RAISE NOTICE 't5 stray clause_revision event caught OK';
END $t5_batch_result_stray_event$;

-- Forslag efter en revision: et citat af en ordinal, der kun findes i det afløste sæt,
-- er ukendt; det aktuelle sæts ordinal accepteres og linkes (Task 3, spec §3.3).
CREATE FUNCTION pg_temp.ip_apply(p_fx jsonb, p_claims jsonb, p_nonce text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_profile text := 'fixture-ip-'||(p_fx->>'record_key'); v_config jsonb; v_sha text; v_auth uuid; v_batch uuid; v_result jsonb; v_payload jsonb;
  v_msha text := encode(extensions.digest(p_nonce,'sha256'),'hex'); v_element text := 'interpretation-proposal:'||(p_fx->>'record_key');
BEGIN
  v_config:=jsonb_build_object('citation_label_template','Synthetic side {page_from}','extractor_version','interpretation-proposal-v1',
    'observation_extraction_method','clause_segment_v1','rendition_key','fixture-r1','rendition_kind','pdf_text_layer',
    'rendition_metadata',jsonb_build_object('edition','fixture','pdf_sha256',repeat('a',64),'pdftotext_version','fixture 0.0'),
    'run_key_prefix','reimport-interpretation-proposal:','schema_version','interpretation-proposal-manifest-v1');
  v_sha:=private.reimport_canonical_json_sha256(v_config);
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES((p_fx->>'source_id')::bigint,v_profile,'interpretation-proposal-v1',v_sha,v_config) ON CONFLICT DO NOTHING;
  v_payload:=jsonb_build_object('source_record_key',p_fx->>'record_key','runner_manifest_sha256',repeat('7',64),'model_version','fixture-model','prompt_version','fixture-prompt','claims',p_claims);
  PERFORM set_config('request.jwt.claim.sub',p_fx->>'actor',true);
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(v_msha,repeat('6',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    (p_fx->>'source_id')::bigint,v_profile,v_sha,'{"person_creates":0,"source_evidence":0,"interpretation_proposals":1}'::jsonb,
    jsonb_build_object(v_element,v_payload),gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch:=public.red_begin_reimport(v_auth,v_msha,repeat('6',64));
  v_result:=public.red_apply_reimport_interpretation_proposal(v_batch,v_element,v_payload);
  PERFORM public.red_finalize_reimport(v_batch);
  RESET role;
  RETURN v_result;
END $$;

DO $t6_proposal_after_revision$
DECLARE fx jsonb; v_text text := 'Romeo Sierra, f. 1841, d. 1890. Gift 1870 m. Tango Uniform.'; v_parent uuid; c jsonb; v_old2 text; v_new1 text; r jsonb;
BEGIN
  fx := pg_temp.se_fixture('CR5', v_text);
  c := pg_temp.ce_clauses(v_text);
  PERFORM pg_temp.ce_apply(fx, pg_temp.ce_payload(fx, c), 'CR5', 'cr5-ce');
  v_parent := pg_temp.parent_of(fx);
  v_old2 := c->1->>'verbatim_sha256';
  PERFORM pg_temp.cr_apply(fx, pg_temp.cr_payload(fx, pg_temp.whole(v_text), 1, private.clause_set_sha256(v_parent,1)), 'cr5-rev1');
  v_new1 := encode(extensions.digest(v_text,'sha256'),'hex');
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.ip_apply(%L::jsonb,%L::jsonb,%L)', fx,
    jsonb_build_array(jsonb_build_object('claim_id','c-old','predicate','person.name','interpretation_kind','property','value','Romeo Sierra',
      'confidence',0.9,'cited_clauses',jsonb_build_array(jsonb_build_object('ordinal',2,'verbatim_sha256',v_old2)),'persona_role','other')), 'cr5-ip1'),
    'REIMPORT_WRITER_CLAUSE_UNKNOWN');
  r := pg_temp.ip_apply(fx, jsonb_build_array(jsonb_build_object('claim_id','c-new','predicate','person.name','interpretation_kind','property','value','Romeo Sierra',
      'confidence',0.9,'cited_clauses',jsonb_build_array(jsonb_build_object('ordinal',1,'verbatim_sha256',v_new1)),'persona_role','other')), 'cr5-ip2');
  IF NOT EXISTS (SELECT 1 FROM private.interpretation_observation io JOIN private.source_observation o ON o.id=io.observation_id
                  WHERE o.parent_observation_id=v_parent AND o.clause_set_seq=2) THEN
    RAISE EXCEPTION 'T6_LINK_NOT_TO_CURRENT_SET: %', r;
  END IF;
  -- Nu citerer et forslag det aktuelle sæt: en ny revision afvises.
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.cr_apply(%L::jsonb,%L::jsonb,%L)', fx,
    pg_temp.cr_payload(fx, c, 2, private.clause_set_sha256(v_parent,2)), 'cr5-rev2'), 'CLAUSE_REVISION_HAS_INTERPRETATIONS');
  RAISE NOTICE 't6 proposal after revision OK';
END $t6_proposal_after_revision$;

-- Prods form (review R1 fund 2): 4.1c's 868 klausuler har clause_set_seq NULL. Skriv sæt 1
-- ad writer-vejen og sæt det til NULL med triggerne slået fra (replica-rollen kræver
-- superbruger som i CI). Revisionen skal behandle NULL som sæt 1 hele vejen.
DO $t7_revision_of_null_set$
DECLARE fx jsonb; v_text text := 'Victor Whiskey, f. 1851, d. 1900. Gift 1880 m. Xray Yankee.'; v_parent uuid; h1 text; r jsonb; v_disp text[]; v_n integer;
BEGIN
  fx := pg_temp.se_fixture('CR7', v_text);
  PERFORM pg_temp.ce_apply(fx, pg_temp.ce_payload(fx, pg_temp.ce_clauses(v_text)), 'CR7', 'cr7-ce');
  v_parent := pg_temp.parent_of(fx);
  h1 := private.clause_set_sha256(v_parent,1);
  PERFORM set_config('session_replication_role','replica',true);
  UPDATE private.source_observation SET clause_set_seq=NULL WHERE parent_observation_id=v_parent;
  PERFORM set_config('session_replication_role','origin',true);
  IF (SELECT count(*) FROM private.source_observation WHERE parent_observation_id=v_parent AND clause_set_seq IS NULL)<>2 THEN
    RAISE EXCEPTION 'T7_FIXTURE_NOT_NULL';
  END IF;
  -- Hashen er den samme, uanset om sæt 1 står som NULL eller 1.
  IF private.clause_set_sha256(v_parent,1) IS DISTINCT FROM h1 THEN RAISE EXCEPTION 'T7_HASH_NULL_DRIFT'; END IF;
  r := pg_temp.cr_apply(fx, pg_temp.cr_payload(fx, pg_temp.whole(v_text), 1, h1), 'cr7-rev1');
  IF (r->>'clause_set_seq')::int<>2 OR (r->>'clauses_replaced')::int<>2 OR r->>'before_clause_set_sha256'<>h1 THEN
    RAISE EXCEPTION 'T7_RESULT: %', r;
  END IF;
  SELECT count(*) INTO v_n FROM private.clause_observation_current WHERE parent_observation_id=v_parent AND clause_set_seq=2;
  IF v_n<>1 OR (SELECT count(*) FROM private.clause_observation_current WHERE parent_observation_id=v_parent)<>1 THEN
    RAISE EXCEPTION 'T7_CURRENT: %', v_n;
  END IF;
  SELECT array_agg(d.disposition ORDER BY o.clause_set_seq NULLS FIRST, o.clause_ordinal) INTO v_disp
    FROM private.clause_disposition_current d JOIN private.source_observation o ON o.id=d.observation_id WHERE o.parent_observation_id=v_parent;
  IF v_disp<>ARRAY['erstattet','erstattet','afventer_fortolkning'] THEN RAISE EXCEPTION 'T7_DISPOSITIONS: %', v_disp; END IF;
  RAISE NOTICE 't7 revision of NULL set OK';
END $t7_revision_of_null_set$;

-- S4 (review R1 fund 3): ét forslagsbatch pr. post pr. kilde. Et andet batch for samme
-- record afvises, også med et andet claim; en anden record går igennem.
DO $t8_s4_one_proposal_batch_per_record$
DECLARE fx jsonb; fx2 jsonb; v_text text := 'Zulu Alfa, f. 1861, d. 1910. Gift 1890 m. Bravo Charlie.'; v_whole text;
BEGIN
  fx := pg_temp.se_fixture('CR8', v_text);
  PERFORM pg_temp.ce_apply(fx, pg_temp.ce_payload(fx, pg_temp.whole(v_text)), 'CR8', 'cr8-ce');
  v_whole := encode(extensions.digest(v_text,'sha256'),'hex');
  PERFORM pg_temp.ip_apply(fx, jsonb_build_array(jsonb_build_object('claim_id','c1','predicate','person.name','interpretation_kind','property','value','Zulu Alfa',
      'confidence',0.9,'cited_clauses',jsonb_build_array(jsonb_build_object('ordinal',1,'verbatim_sha256',v_whole)),'persona_role','other')), 'cr8-ip1');
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.ip_apply(%L::jsonb,%L::jsonb,%L)', fx,
    jsonb_build_array(jsonb_build_object('claim_id','c2','predicate','person.name','interpretation_kind','property','value','Zulu A.',
      'confidence',0.8,'cited_clauses',jsonb_build_array(jsonb_build_object('ordinal',1,'verbatim_sha256',v_whole)),'persona_role','other')), 'cr8-ip2'),
    'REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS');
  -- Kontrol: vagten spærrer ikke andre records (se_fixture giver hver nøgle sin egen kilde).
  fx2 := pg_temp.se_fixture('CR8b', v_text);
  PERFORM pg_temp.ce_apply(fx2, pg_temp.ce_payload(fx2, pg_temp.whole(v_text)), 'CR8b', 'cr8b-ce');
  PERFORM pg_temp.ip_apply(fx2, jsonb_build_array(jsonb_build_object('claim_id','c1','predicate','person.name','interpretation_kind','property','value','Zulu Alfa',
      'confidence',0.9,'cited_clauses',jsonb_build_array(jsonb_build_object('ordinal',1,'verbatim_sha256',v_whole)),'persona_role','other')), 'cr8b-ip1');
  RAISE NOTICE 't8 S4 one proposal batch per record OK';
END $t8_s4_one_proposal_batch_per_record$;

ROLLBACK;
