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

ROLLBACK;
