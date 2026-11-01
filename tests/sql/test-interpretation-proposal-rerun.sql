-- Trin 6a, Task 6 (spec §4.4 pkt. 6): genkørselskontrakten efter en kildetekst-revision. Forslags-writerens S4
-- (REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS) åbner kun efter en faktisk source_text_revision-event, der har
-- forældet alle nøgler fra recordens tidligere forslags-events, og hvis tekstversion er helpostens gældende. Nøglen
-- binder til helpostens tekstversionsnummer (key_version 2); uden tekstversion er nøglen uændret version 1.
-- Kræver kontrakt v2 (reimport-writer-v2-bootstrap.sql) og 1939-bootstrap som test-source-text-revision.sql.
-- Alt syntetisk. Revisionen kræver READ COMMITTED (writerens isolationsvagt), mens forslagsprojektionens guard kræver
-- REPEATABLE READ og READ ONLY; de to kan ikke dele en transaktion. Derfor: S4-testene i én READ COMMITTED-transaktion,
-- der rulles tilbage; B → C → B-posten (kilde -66901) skrives og committes i sin egen READ COMMITTED-transaktion; og
-- projektionen læser den committede post i en REPEATABLE READ READ ONLY-transaktion. Fixtures og hjælpere oprettes
-- uden for transaktionerne (pg_temp lever i sessionen). Filen køres én gang pr. base (den committede post har faste id'er).
\set ON_ERROR_STOP on
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/source-text-revision.sql

CREATE FUNCTION pg_temp.expect_error(p_sql text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM IS NULL OR SQLERRM NOT LIKE p_token||'%' THEN
      RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_WRONG_ERROR: expected % got %', p_token, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_NO_ERROR: expected %', p_token;
END $$;

-- Fixturens sæt 1 er skrevet direkte (f5b_post) uden klausuldispositioner; forslags-writeren kræver en maskinel
-- disposition med batch og manifest pr. citeret klausul, som klausul-writeren ville have skrevet.
CREATE FUNCTION pg_temp.rr_dispositions(fx jsonb) RETURNS void LANGUAGE sql AS $$
  INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence)
  SELECT o.id,1,'afventer_fortolkning','machine',
         jsonb_build_object('batch_id',gen_random_uuid(),'manifest_sha256',repeat('8',64),'element_id','clause-evidence:'||(fx->>'record_key'))
    FROM private.source_observation o
   WHERE o.parent_observation_id=(fx->>'helpost')::uuid AND coalesce(o.clause_set_seq,1)=1
     AND NOT EXISTS (SELECT 1 FROM private.clause_disposition d WHERE d.observation_id=o.id)
$$;

-- Et person.name-claim, der citerer det aktuelle sæts klausul p_ordinal med dens aktuelle hash.
CREATE FUNCTION pg_temp.rr_claim(fx jsonb, p_claim text, p_ordinal int, p_value text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('claim_id',md5(p_claim),'predicate','person.name','interpretation_kind','property','value',p_value,
    'confidence',0.9,'persona_role','other',
    'cited_clauses',jsonb_build_array(jsonb_build_object('ordinal',p_ordinal,
      'verbatim_sha256',encode(extensions.digest(c.verbatim_text,'sha256'),'hex'))))
    FROM private.clause_observation_current c
   WHERE c.parent_observation_id=(fx->>'helpost')::uuid AND c.clause_ordinal=p_ordinal
$$;

-- Hele forslagskæden (autorisation → begin → apply → finalize) for fixturens record. Returnerer writerens svar, batch
-- og den skrevne event-payload.
CREATE FUNCTION pg_temp.rr_propose(fx jsonb, p_claims jsonb, p_nonce text, p_cfg jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_profile text:='t6-proposal-'||(fx->>'record_key'); v_config jsonb; v_sha text; v_auth uuid; v_batch uuid;
  v_result jsonb; v_payload jsonb; v_msha text:=encode(extensions.digest('t6:'||p_nonce,'sha256'),'hex');
  v_element text:='interpretation-proposal:'||(fx->>'record_key'); v_event jsonb;
BEGIN
  v_config:=jsonb_build_object('citation_label_template','Synthetic side {page_from}','extractor_version','interpretation-proposal-v1',
    'observation_extraction_method','clause_segment_v1','rendition_key','fixture-r1','rendition_kind','pdf_text_layer',
    'rendition_metadata',jsonb_build_object('edition','fixture','pdf_sha256',repeat('a',64),'pdftotext_version','fixture 0.0'),
    'run_key_prefix','reimport-interpretation-proposal:','schema_version','interpretation-proposal-manifest-v1');
  v_config:=v_config||p_cfg;
  v_sha:=private.reimport_canonical_json_sha256(v_config);
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
    VALUES((fx->>'source')::bigint,v_profile,'interpretation-proposal-v1',v_sha,v_config) ON CONFLICT DO NOTHING;
  v_payload:=jsonb_build_object('source_record_key',fx->>'record_key','runner_manifest_sha256',repeat('7',64),
    'model_version','fixture-model','prompt_version','fixture-prompt','claims',p_claims);
  PERFORM set_config('request.jwt.claim.sub',fx->>'actor',true);
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(v_msha,repeat('6',64),
    jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    (fx->>'source')::bigint,v_profile,v_sha,'{"person_creates":0,"source_evidence":0,"interpretation_proposals":1}'::jsonb,
    jsonb_build_object(v_element,v_payload),gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch:=public.red_begin_reimport(v_auth,v_msha,repeat('6',64));
  v_result:=public.red_apply_reimport_interpretation_proposal(v_batch,v_element,v_payload);
  PERFORM public.red_finalize_reimport(v_batch);
  RESET role;
  SELECT payload INTO v_event FROM private.reimport_event WHERE batch_id=v_batch AND operation='interpretation_proposal';
  RETURN v_result||jsonb_build_object('batch_id',v_batch,'event',v_event);
END $$;

-- Nøglen for et claim i en forslags-event.
CREATE FUNCTION pg_temp.rr_key(p_result jsonb, p_claim text) RETURNS uuid LANGUAGE sql AS $$
  SELECT (c->>'interpretation_key')::uuid FROM jsonb_array_elements(p_result->'event'->'result_receipt'->'claims') c
   WHERE c->>'claim_id'=md5(p_claim)
$$;

-- Revision af fixturens helpost til p_new (klausuler p_parts) gennem hele writer-kæden; mængderne måles nu.
CREATE FUNCTION pg_temp.rr_revise(fx jsonb, p_new text, p_parts text[], p_nonce text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  r:=pg_temp.t5_apply(fx,pg_temp.t5_payload(fx,p_new,p_parts),p_nonce);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  RETURN r;
END $$;

-- Trin 6c-1 (spec §4.4): ekstra accepterede forankringer af en anden slags indeni helpostens spænd, som 1939's poster
-- har (helpost + sidehoved-/underforekomster). p_kind/p_inside styrer slags og om spændet ligger indeni helposten.
CREATE FUNCTION pg_temp.rr_extra_anchor(fx jsonb, p_key text, p_kind text, p_from int, p_to int) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_occ uuid; v_h private.source_observation%ROWTYPE; v_rend uuid; v_run uuid:=(fx->'src'->>'run')::uuid;
BEGIN
  SELECT * INTO v_h FROM private.source_observation WHERE id=(fx->>'helpost')::uuid;
  SELECT o.rendition_id INTO v_rend FROM private.source_record_occurrence o WHERE o.id=v_h.occurrence_id;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,
    physical_fingerprint,structural_fingerprint,extraction_run_id)
  VALUES(v_rend,p_key,v_h.page_from,v_h.page_to,p_from,p_to,repeat('x',p_to-p_from),repeat('3',64),repeat('4',64),v_run) RETURNING id INTO v_occ;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,
    extraction_method,extraction_run_id)
  VALUES(v_occ,p_kind,v_h.page_from,v_h.page_to,p_from,p_to,repeat('x',p_to-p_from),'clear','fixture',v_run);
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
  VALUES(v_occ,(fx->'post'->>'record')::uuid,'accepted','{"fixture":true}'::jsonb,1,gen_random_uuid(),'fixture');
END $$;

-- Fixturen: t5-posten 'Anna Alfa. Gift med Bo Beta.' uden publicering og uden dødsbinding.
CREATE FUNCTION pg_temp.rr_fixture(p_base bigint, p_actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE fx jsonb;
BEGIN
  fx:=pg_temp.t5_post(p_base,p_actor,false,false);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM pg_temp.rr_dispositions(fx);
  RETURN fx;
END $$;

-- Hjælpere til test_projection_follows_key_version (nederst); oprettes her, fordi projektionen kører READ ONLY.
CREATE FUNCTION pg_temp.rr_cited(p_interpretation uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_agg(jsonb_build_object('ordinal',o.clause_ordinal,'verbatim_sha256',encode(extensions.digest(o.verbatim_text,'sha256'),'hex'))
                   ORDER BY io.ordinal)
    FROM private.interpretation_observation io JOIN private.source_observation o ON o.id=io.observation_id
   WHERE io.interpretation_id=p_interpretation
$$;
CREATE FUNCTION pg_temp.rr_assert_projection(p jsonb, p_source bigint) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v record; v_rows int:=0; v_receipt int; v_current int; v_naive uuid;
BEGIN
  IF (p->>'source_id')::bigint IS DISTINCT FROM p_source THEN RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: projektionens kilde'; END IF;
  SELECT t.version INTO v_current FROM private.source_observation_text t
   WHERE t.id=(SELECT c.text_id FROM private.interpretation_current ic JOIN private.interpretation_observation io ON io.interpretation_id=ic.id
                 JOIN private.source_observation o ON o.id=io.observation_id
                 CROSS JOIN LATERAL private.helpost_text_current(o.parent_observation_id) c
                WHERE ic.source_id=p_source AND ic.status='proposed' AND ic.method='model' LIMIT 1);
  IF v_current IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: gældende tekstversion %',v_current; END IF;
  FOR v IN
    SELECT r AS row, (e->>'key_version')::int AS key_version, i.id, i.interpretation_key, i.predicate, i.value
      FROM jsonb_array_elements(p->'interpretations') r
      JOIN private.interpretation i ON i.id=(r->>'interpretation_id')::uuid
      JOIN private.reimport_event e0 ON e0.operation='interpretation_proposal'
       AND e0.payload->'result_receipt'->'claims' @> jsonb_build_array(jsonb_build_object('interpretation_key',r->>'interpretation_key'))
      CROSS JOIN LATERAL (SELECT e0.payload AS e) x
  LOOP
    v_rows:=v_rows+1;
    IF (v.row->>'key_matches')::boolean IS NOT TRUE THEN
      RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: key_matches falsk for nøgle % (key_version %)',v.interpretation_key,v.key_version;
    END IF;
    IF v.key_version=1 THEN
      v_naive:=private.deterministic_uuid(private.interpretation_proposal_key_material_v2(p_source,v.row->>'record_key',v.predicate,
        pg_temp.rr_cited(v.id),v.value,v_current));
    ELSE
      v_naive:=private.interpretation_proposal_key(p_source,v.row->>'record_key',v.predicate,pg_temp.rr_cited(v.id),v.value);
    END IF;
    IF v_naive=v.interpretation_key THEN
      RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: den forkerte genberegning rammer nøglen %',v.interpretation_key;
    END IF;
  END LOOP;
  IF v_rows<>5 THEN RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: % forslagsrækker, ventede 5',v_rows; END IF;
  SELECT count(*) INTO v_receipt
    FROM jsonb_array_elements(p->'proposal_events') e, jsonb_array_elements(e->'result_receipt'->'claims') c,
         jsonb_array_elements(p->'interpretations') r
   WHERE r->>'interpretation_key'=c->>'interpretation_key' AND (r->>'version')::int=1
     AND r->>'key_material_sha256'=c->>'key_material_sha256';
  IF v_receipt<>3 THEN RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: % nøglematerialer lig kvitteringen, ventede 3',v_receipt; END IF;
END $$;

BEGIN ISOLATION LEVEL READ COMMITTED;

-- test_s4_still_blocks_unrevised_post: uden revision afvises et nyt forslag for posten, også med samme claim, og
-- forslaget uden tekstversion bærer nøgle version 1 (v1-funktionen, uændret).
DO $t$
DECLARE fx jsonb; r jsonb; v_key uuid; v_claim jsonb;
BEGIN
  fx:=pg_temp.rr_fixture(-66101,'11000000-0000-0000-0000-00000006a601');
  v_claim:=pg_temp.rr_claim(fx,'c1',1,'Anna Alfa');
  r:=pg_temp.rr_propose(fx,jsonb_build_array(v_claim),'s4-unrevised-1');
  v_key:=pg_temp.rr_key(r,'c1');
  IF v_key IS DISTINCT FROM private.interpretation_proposal_key((fx->>'source')::bigint,fx->>'record_key','person.name',
                                                                 v_claim->'cited_clauses',to_jsonb('Anna Alfa'::text))
     OR (r->'event'->>'key_version')::int IS DISTINCT FROM 1 OR NOT (r->'event' ? 'text_version')
     OR r->'event'->'text_version'<>'null'::jsonb THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: v1-forslaget %',r->'event';
  END IF;
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.rr_propose(%L::jsonb,%L::jsonb,%L)',fx,jsonb_build_array(v_claim),'s4-unrevised-2'),
    'REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS');
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.rr_propose(%L::jsonb,%L::jsonb,%L)',fx,
    jsonb_build_array(pg_temp.rr_claim(fx,'c2',2,'Bo Beta')),'s4-unrevised-3'),'REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS');
  RAISE NOTICE 'OK: test_s4_still_blocks_unrevised_post';
END $t$;

-- test_s4_opens_after_text_revision: efter en revision, der forælder forslagets nøgle, accepteres et forslag med samme
-- ordinal og værdi; nøglen er v2 bundet til tekstversion 1 og ≠ den forældede. Uden ny revision lukker S4 igen.
DO $t$
DECLARE fx jsonb; r1 jsonb; rev jsonb; r2 jsonb; k1 uuid; k2 uuid; v_claim jsonb; v_material text; v_tv record;
BEGIN
  fx:=pg_temp.rr_fixture(-66201,'11000000-0000-0000-0000-00000006a602');
  r1:=pg_temp.rr_propose(fx,jsonb_build_array(pg_temp.rr_claim(fx,'c1',1,'Anna Alfa')),'s4-open-1');
  k1:=pg_temp.rr_key(r1,'c1');
  rev:=pg_temp.rr_revise(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.'],'s4-open-rev');
  IF NOT rev->'superseded_keys' @> to_jsonb(ARRAY[k1::text]) THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: revisionen forældede ikke forslaget %',rev->'superseded_keys';
  END IF;
  v_claim:=pg_temp.rr_claim(fx,'c1',1,'Anna Alfa');
  r2:=pg_temp.rr_propose(fx,jsonb_build_array(v_claim),'s4-open-2');
  k2:=pg_temp.rr_key(r2,'c1');
  SELECT * INTO v_tv FROM private.source_observation_text WHERE id=(rev->>'text_id')::uuid;
  v_material:=private.interpretation_proposal_key_material_v2((fx->>'source')::bigint,fx->>'record_key','person.name',
    v_claim->'cited_clauses',to_jsonb('Anna Alfa'::text),v_tv.version);
  IF k2 IS NULL OR k2=k1 OR k2<>private.deterministic_uuid(v_material)
     OR (SELECT c->>'key_material_sha256' FROM jsonb_array_elements(r2->'event'->'result_receipt'->'claims') c)
        <>encode(extensions.digest(convert_to(v_material,'UTF8'),'sha256'),'hex')
     OR (r2->'event'->>'key_version')::int IS DISTINCT FROM 2 OR (r2->'event'->>'text_version')::int IS DISTINCT FROM v_tv.version
     OR v_tv.version<>1 THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: v2-forslaget % (k1 %)',r2->'event',k1;
  END IF;
  IF (SELECT status FROM private.interpretation_current WHERE interpretation_key=k1)<>'superseded'
     OR (SELECT status FROM private.interpretation_current WHERE interpretation_key=k2)<>'proposed' THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: status efter genkørsel';
  END IF;
  -- Genkørslen er brugt: et tredje forslag uden ny revision afvises.
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.rr_propose(%L::jsonb,%L::jsonb,%L)',fx,
    jsonb_build_array(pg_temp.rr_claim(fx,'c9',2,'Bo Beta')),'s4-open-3'),'REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS');
  RAISE NOTICE 'OK: test_s4_opens_after_text_revision';
END $t$;

-- test_s4_blocks_if_any_key_not_superseded_by_revision: én af forslagets nøgler blev afvist af en redaktør før
-- revisionen og er derfor ikke i revisionens superseded_keys; S4 forbliver lukket.
DO $t$
DECLARE fx jsonb; r1 jsonb; rev jsonb; k2 uuid; v_id uuid;
BEGIN
  fx:=pg_temp.rr_fixture(-66301,'11000000-0000-0000-0000-00000006a603');
  r1:=pg_temp.rr_propose(fx,jsonb_build_array(pg_temp.rr_claim(fx,'c1',1,'Anna Alfa'),pg_temp.rr_claim(fx,'c2',2,'Bo Beta')),'s4-partial-1');
  k2:=pg_temp.rr_key(r1,'c2');
  SELECT id INTO v_id FROM private.interpretation_current WHERE interpretation_key=k2;
  PERFORM set_config('request.jwt.claim.sub',fx->>'actor',true);
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_decide_interpretation(v_id,1,'rejected','{"basis":"t6 fixture: forkert navn"}');
  RESET ROLE;
  rev:=pg_temp.rr_revise(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.'],'s4-partial-rev');
  IF rev->'superseded_keys' @> to_jsonb(ARRAY[k2::text]) OR NOT rev->'superseded_keys' @> to_jsonb(ARRAY[pg_temp.rr_key(r1,'c1')::text]) THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: revisionens nøgler %',rev->'superseded_keys';
  END IF;
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.rr_propose(%L::jsonb,%L::jsonb,%L)',fx,
    jsonb_build_array(pg_temp.rr_claim(fx,'c1',1,'Anna Alfa')),'s4-partial-2'),'REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS');
  RAISE NOTICE 'OK: test_s4_blocks_if_any_key_not_superseded_by_revision';
END $t$;

-- test_s4_not_opened_by_forged_basis: alle forslagets nøgler forældes med grundlaget source_text_revision og en
-- foretrukken tekstversion indsættes, begge direkte som tabelejer, men uden revisions-event. S4 forbliver lukket.
DO $t$
DECLARE fx jsonb; r1 jsonb; k1 uuid; v_help private.source_observation%ROWTYPE; v_rend uuid; v_text uuid;
BEGIN
  fx:=pg_temp.rr_fixture(-66401,'11000000-0000-0000-0000-00000006a604');
  r1:=pg_temp.rr_propose(fx,jsonb_build_array(pg_temp.rr_claim(fx,'c1',1,'Anna Alfa')),'s4-forged-1');
  k1:=pg_temp.rr_key(r1,'c1');
  SELECT * INTO v_help FROM private.source_observation WHERE id=(fx->>'helpost')::uuid;
  SELECT o.rendition_id INTO v_rend FROM private.source_record_occurrence o WHERE o.id=v_help.occurrence_id;
  INSERT INTO private.source_observation_text(observation_id,rendition_id,version,verbatim_text,char_from,char_to,is_preferred)
    VALUES (v_help.id,v_rend,1,'Anna Alfa. Gift m. Bo Beta.',v_help.char_from,v_help.char_to,true) RETURNING id INTO v_text;
  IF (SELECT text_id FROM private.helpost_text_current(v_help.id)) IS DISTINCT FROM v_text THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: den forfalskede tekstversion er ikke gældende';
  END IF;
  IF private.supersede_for_text_revision(ARRAY[k1],(fx->>'actor')::uuid,'forfalsker',
       jsonb_build_object('text_id_after',v_text,'forged',true))<>1 THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: forfalskningen forældede ikke nøglen';
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF (SELECT decision_evidence->>'basis' FROM private.interpretation_current WHERE interpretation_key=k1)<>'source_text_revision' THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: grundlaget blev ikke forfalsket';
  END IF;
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.rr_propose(%L::jsonb,%L::jsonb,%L)',fx,
    jsonb_build_array(pg_temp.rr_claim(fx,'c1',1,'Anna Alfa')),'s4-forged-2'),'REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS');
  RAISE NOTICE 'OK: test_s4_not_opened_by_forged_basis';
END $t$;

-- test_s4_not_opened_by_editor_supersede_after_revision (vagt i: nøglerne skal stå i en revisions superseded_keys):
-- efter en ægte revision og et nyt forslag forælder en redaktør det nye forslag med et ikke-reserveret grundlag.
-- Nøglen er forældet, og den gældende tekst er skrevet af revisionen, men ingen revision har forældet nøglen.
-- Det tredje forslag er et andet claim (anden ordinal og værdi), så nøglekollisionen med k2 ikke er det, der spærrer.
DO $t$
DECLARE fx jsonb; r2 jsonb; k2 uuid; v_id uuid;
BEGIN
  fx:=pg_temp.rr_fixture(-66601,'11000000-0000-0000-0000-00000006a606');
  PERFORM pg_temp.rr_propose(fx,jsonb_build_array(pg_temp.rr_claim(fx,'c1',1,'Anna Alfa')),'editor-1');
  PERFORM pg_temp.rr_revise(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.'],'editor-rev');
  r2:=pg_temp.rr_propose(fx,jsonb_build_array(pg_temp.rr_claim(fx,'c1',1,'Anna Alfa')),'editor-2');
  k2:=pg_temp.rr_key(r2,'c1');
  SELECT id INTO v_id FROM private.interpretation_current WHERE interpretation_key=k2;
  PERFORM set_config('request.jwt.claim.sub',fx->>'actor',true);
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_decide_interpretation(v_id,1,'superseded','{"basis":"redaktør: genudtræk ønskes"}');
  RESET ROLE;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF (SELECT status FROM private.interpretation_current WHERE interpretation_key=k2)<>'superseded' THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: redaktøren forældede ikke k2';
  END IF;
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.rr_propose(%L::jsonb,%L::jsonb,%L)',fx,
    jsonb_build_array(pg_temp.rr_claim(fx,'c9',2,'Bo Beta')),'editor-3'),'REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS');
  RAISE NOTICE 'OK: test_s4_not_opened_by_editor_supersede_after_revision';
END $t$;

-- test_s4_not_opened_by_text_replaced_after_revision (vagt iii: den gældende tekst skal være skrevet af en revision):
-- en ægte revision har forældet forslagets nøgle, men tabelejeren lægger bagefter en ny foretrukken tekstversion
-- direkte. Nøgledækningen holder, men den gældende tekst er ikke revideret; S4 forbliver lukket.
DO $t$
DECLARE fx jsonb; rev jsonb; v_prev private.source_observation_text%ROWTYPE; v_text uuid;
BEGIN
  fx:=pg_temp.rr_fixture(-66701,'11000000-0000-0000-0000-00000006a607');
  PERFORM pg_temp.rr_propose(fx,jsonb_build_array(pg_temp.rr_claim(fx,'c1',1,'Anna Alfa')),'replaced-1');
  rev:=pg_temp.rr_revise(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.'],'replaced-rev');
  SELECT * INTO v_prev FROM private.source_observation_text WHERE id=(rev->>'text_id')::uuid;
  INSERT INTO private.source_observation_text(observation_id,rendition_id,version,verbatim_text,char_from,char_to,is_preferred,supersedes_id)
    VALUES (v_prev.observation_id,v_prev.rendition_id,v_prev.version+1,'Anna Alfa. Gift m. B. Beta.',v_prev.char_from,v_prev.char_to,true,v_prev.id)
    RETURNING id INTO v_text;
  IF (SELECT text_id FROM private.helpost_text_current(v_prev.observation_id)) IS DISTINCT FROM v_text THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: den direkte tekstversion er ikke gældende';
  END IF;
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.rr_propose(%L::jsonb,%L::jsonb,%L)',fx,
    jsonb_build_array(pg_temp.rr_claim(fx,'c1',1,'Anna Alfa')),'replaced-2'),'REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS');
  RAISE NOTICE 'OK: test_s4_not_opened_by_text_replaced_after_revision';
END $t$;

-- Trin 6c-1 (spec §4.4): forslagswriteren vælger helposten med helpost-reglen og batchprofilens helpost-slags, ikke
-- med »præcis én forankring«. En post med tre forankringer (helpost + to underforekomster indeni) accepteres, og
-- nøglen er den samme som for en post med én forankring (nøglen afhænger ikke af forankringerne).
DO $t$
DECLARE fx jsonb; r jsonb; v_claim jsonb; v_h private.source_observation%ROWTYPE; v_int uuid; v_bad int;
BEGIN
  fx:=pg_temp.rr_fixture(-66801,'11000000-0000-0000-0000-00000006a801');
  SELECT * INTO v_h FROM private.source_observation WHERE id=(fx->>'helpost')::uuid;
  PERFORM pg_temp.rr_extra_anchor(fx,'extra-a','fact',v_h.char_from,v_h.char_from+2);
  PERFORM pg_temp.rr_extra_anchor(fx,'extra-b','fact',v_h.char_from+3,v_h.char_to);
  IF (SELECT count(*) FROM private.source_record_anchor_current WHERE source_record_id=(fx->'post'->>'record')::uuid
        AND decision_status='accepted')<>3 THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: fixturen har ikke tre forankringer';
  END IF;
  v_claim:=pg_temp.rr_claim(fx,'c1',1,'Anna Alfa');
  r:=pg_temp.rr_propose(fx,jsonb_build_array(v_claim),'helpost-3anchors');
  IF pg_temp.rr_key(r,'c1') IS DISTINCT FROM private.interpretation_proposal_key((fx->>'source')::bigint,fx->>'record_key',
       'person.name',v_claim->'cited_clauses',to_jsonb('Anna Alfa'::text)) THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: nøglen for en post med tre forankringer';
  END IF;
  SELECT i.id INTO v_int FROM private.interpretation_current i WHERE i.interpretation_key=pg_temp.rr_key(r,'c1');
  SELECT count(*) INTO v_bad FROM private.interpretation_observation io JOIN private.source_observation o ON o.id=io.observation_id
   WHERE io.interpretation_id=v_int AND o.parent_observation_id IS DISTINCT FROM v_h.id;
  IF v_bad<>0 OR NOT EXISTS (SELECT 1 FROM private.interpretation_observation WHERE interpretation_id=v_int) THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: forslaget peger ikke på helpostens klausuler';
  END IF;
  RAISE NOTICE 'OK: test_proposal_helpost_rule_three_anchors';
END $t$;

-- To accepterede helposter af samme slags er flertydige; en underforekomst, der stikker ud, er afvist; og
-- helpost-slags læses fra profilen (en profil med slags 'person' finder ingen helpost i en person_post-post).
DO $t$
DECLARE fx jsonb; v_h private.source_observation%ROWTYPE;
BEGIN
  fx:=pg_temp.rr_fixture(-66811,'11000000-0000-0000-0000-00000006a811');
  SELECT * INTO v_h FROM private.source_observation WHERE id=(fx->>'helpost')::uuid;
  PERFORM pg_temp.rr_extra_anchor(fx,'extra-c','person_post',v_h.char_to+10,v_h.char_to+20);
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.rr_propose(%L::jsonb,%L::jsonb,%L)',fx,
    jsonb_build_array(pg_temp.rr_claim(fx,'c1',1,'Anna Alfa')),'helpost-ambig'),'RECORD_HELPOST_AMBIGUOUS');
  fx:=pg_temp.rr_fixture(-66821,'11000000-0000-0000-0000-00000006a821');
  SELECT * INTO v_h FROM private.source_observation WHERE id=(fx->>'helpost')::uuid;
  PERFORM pg_temp.rr_extra_anchor(fx,'extra-d','fact',v_h.char_to-2,v_h.char_to+5);
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.rr_propose(%L::jsonb,%L::jsonb,%L)',fx,
    jsonb_build_array(pg_temp.rr_claim(fx,'c1',1,'Anna Alfa')),'helpost-outside'),'RECORD_HELPOST_SUBOCCURRENCE_OUTSIDE');
  fx:=pg_temp.rr_fixture(-66831,'11000000-0000-0000-0000-00000006a831');
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.rr_propose(%L::jsonb,%L::jsonb,%L,%L::jsonb)',fx,
    jsonb_build_array(pg_temp.rr_claim(fx,'c1',1,'Anna Alfa')),'helpost-kind','{"helpost_observation_kind":"person"}'),
    'RECORD_HELPOST_AMBIGUOUS');
  RAISE NOTICE 'OK: test_proposal_helpost_rule_errors';
END $t$;

-- Trin 6c-1 (spec §4.4, Review Focus 2): 1939's realistiske form. Profilen har helpost-slags 'person', helposten er
-- en 'person'-observation med flere accepterede forankringer (helpost + underforekomster), personaen har en primary-
-- mention på helposten, og et principal-claim skrives. Fixturens helpost er person_post; slagset ændres her som
-- tabelejer (append-only-triggeren slås fra og til inden for den rullede transaktion). Samme resultat med
-- forankringerne indsat i omvendt rækkefølge.
CREATE FUNCTION pg_temp.rr_person_helpost(p_base bigint, p_actor uuid, p_reverse boolean) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE fx jsonb; r jsonb; v_h private.source_observation%ROWTYPE; v_claim jsonb; v_int private.interpretation%ROWTYPE;
  v_persona uuid; v_bad int; v_n int;
BEGIN
  fx:=pg_temp.rr_fixture(p_base,p_actor);
  ALTER TABLE private.source_observation DISABLE TRIGGER trg_source_observation_append_only;
  UPDATE private.source_observation SET observation_kind='person' WHERE id=(fx->>'helpost')::uuid;
  ALTER TABLE private.source_observation ENABLE TRIGGER trg_source_observation_append_only;
  SELECT * INTO v_h FROM private.source_observation WHERE id=(fx->>'helpost')::uuid;
  IF p_reverse THEN
    PERFORM pg_temp.rr_extra_anchor(fx,'p-b','fact',v_h.char_from+3,v_h.char_to);
    PERFORM pg_temp.rr_extra_anchor(fx,'p-a','marriage',v_h.char_from,v_h.char_from+2);
  ELSE
    PERFORM pg_temp.rr_extra_anchor(fx,'p-a','marriage',v_h.char_from,v_h.char_from+2);
    PERFORM pg_temp.rr_extra_anchor(fx,'p-b','fact',v_h.char_from+3,v_h.char_to);
  END IF;
  SELECT spm.persona_id INTO v_persona FROM private.source_mention sm JOIN private.source_persona_mention spm ON spm.mention_id=sm.id
   WHERE sm.observation_id=v_h.id AND spm.mention_role='primary';
  IF v_persona IS NULL OR (SELECT count(*) FROM private.source_record_anchor_current WHERE source_record_id=(fx->'post'->>'record')::uuid
        AND decision_status='accepted')<>3 THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: person-helpost-fixturen';
  END IF;
  v_claim:=jsonb_set(pg_temp.rr_claim(fx,'c1',1,'Anna Alfa'),'{persona_role}','"principal"');
  r:=pg_temp.rr_propose(fx,jsonb_build_array(v_claim),'person-helpost-'||p_reverse::text,'{"helpost_observation_kind":"person"}');
  SELECT * INTO v_int FROM private.interpretation_current WHERE interpretation_key=pg_temp.rr_key(r,'c1');
  IF v_int.id IS NULL OR v_int.source_persona_id IS DISTINCT FROM v_persona THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: forslagets persona';
  END IF;
  SELECT count(*), count(*) FILTER (WHERE o.parent_observation_id IS DISTINCT FROM v_h.id) INTO v_n,v_bad
    FROM private.interpretation_observation io JOIN private.source_observation o ON o.id=io.observation_id WHERE io.interpretation_id=v_int.id;
  IF v_n<>1 OR v_bad<>0 THEN RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: klausuler under helposten (% / %)',v_n,v_bad; END IF;
  RETURN jsonb_build_object('n',v_n,'status',v_int.status,'role_ok',true);
END $$;
DO $t$
DECLARE a jsonb; b jsonb;
BEGIN
  a:=pg_temp.rr_person_helpost(-66851,'11000000-0000-0000-0000-00000006a851',false);
  b:=pg_temp.rr_person_helpost(-66861,'11000000-0000-0000-0000-00000006a861',true);
  IF a IS DISTINCT FROM b THEN RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: forankringsrækkefølge % %',a,b; END IF;
  RAISE NOTICE 'OK: test_proposal_person_helpost_principal';
END $t$;

-- 2018-20 uændret: en post med én forankring og helpost-slags person_post (profilens standard) giver samme nøgle og
-- nøglemateriale-hash som før ændringen (værdierne er taget fra en base med writeren fra main).
DO $t$
DECLARE fx jsonb; r jsonb; v_k uuid; v_m text;
BEGIN
  fx:=pg_temp.rr_fixture(-66841,'11000000-0000-0000-0000-00000006a841');
  r:=pg_temp.rr_propose(fx,jsonb_build_array(pg_temp.rr_claim(fx,'c1',1,'Anna Alfa')),'helpost-2018-20');
  v_k:=pg_temp.rr_key(r,'c1');
  SELECT c->>'key_material_sha256' INTO v_m FROM jsonb_array_elements(r->'event'->'result_receipt'->'claims') c LIMIT 1;
  IF v_k IS DISTINCT FROM '2626879c-8daf-5f20-b880-8287c8f19bcb'::uuid
     OR v_m IS DISTINCT FROM '2626879c8daf3f2078808287c8f19bcb2fa1bb70645f0bb4300ef741b8bef800' THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: 2018-20-nøglen er ændret (% %)',v_k,v_m;
  END IF;
  RAISE NOTICE 'OK: test_proposal_2018_20_unchanged';
END $t$;

ROLLBACK;

-- test_key_v2_b_c_b: tekstvejen B → C → B med et forslag før den første og efter hver revision, samme ordinal og
-- værdi. Alle tre accepteres med tre forskellige nøgler: v1, v2 med version 1 og v2 med version 2. Committes, så
-- projektionen nedenfor kan læse posten i sin egen REPEATABLE READ-transaktion.
BEGIN ISOLATION LEVEL READ COMMITTED;
DO $t$
DECLARE fx jsonb; v_b text:='Anna Alfa. Gift med Bo Beta.'; v_c text:='Anna Alfa. Gift m. Bo Beta.';
  r1 jsonb; r2 jsonb; r3 jsonb; rev1 jsonb; rev2 jsonb; k1 uuid; k2 uuid; k3 uuid; v_claim jsonb;
BEGIN
  fx:=pg_temp.rr_fixture(-66901,'11000000-0000-0000-0000-00000006a605');
  IF fx->>'text'<>v_b THEN RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: fixturens tekst'; END IF;
  r1:=pg_temp.rr_propose(fx,jsonb_build_array(pg_temp.rr_claim(fx,'c1',1,'Anna Alfa')),'bcb-1');
  rev1:=pg_temp.rr_revise(fx,v_c,ARRAY['Anna Alfa.','Gift m. Bo Beta.'],'bcb-rev1');
  r2:=pg_temp.rr_propose(fx,jsonb_build_array(pg_temp.rr_claim(fx,'c1',1,'Anna Alfa')),'bcb-2');
  rev2:=pg_temp.rr_revise(fx,v_b,ARRAY['Anna Alfa.','Gift med Bo Beta.'],'bcb-rev2');
  v_claim:=pg_temp.rr_claim(fx,'c1',1,'Anna Alfa');
  r3:=pg_temp.rr_propose(fx,jsonb_build_array(v_claim),'bcb-3');
  k1:=pg_temp.rr_key(r1,'c1'); k2:=pg_temp.rr_key(r2,'c1'); k3:=pg_temp.rr_key(r3,'c1');
  IF k1 IS NULL OR k2 IS NULL OR k3 IS NULL OR k1=k2 OR k2=k3 OR k1=k3 THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: nøglerne % % %',k1,k2,k3;
  END IF;
  IF (rev1->>'text_version')::int<>1 OR (rev2->>'text_version')::int<>2
     OR (r1->'event'->>'key_version')::int<>1 OR (r2->'event'->>'key_version')::int<>2 OR (r3->'event'->>'key_version')::int<>2
     OR (r2->'event'->>'text_version')::int<>1 OR (r3->'event'->>'text_version')::int<>2
     OR NOT rev2->'superseded_keys' @> to_jsonb(ARRAY[k2::text]) THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: versioner % % % %',rev1->>'text_version',rev2->>'text_version',r2->'event',r3->'event';
  END IF;
  -- Tekst B igen, men nøglen er ikke v1-nøglen: den binder til versionsnummeret, ikke til teksten.
  IF k3<>private.deterministic_uuid(private.interpretation_proposal_key_material_v2((fx->>'source')::bigint,fx->>'record_key',
       'person.name',v_claim->'cited_clauses',to_jsonb('Anna Alfa'::text),2)) THEN
    RAISE EXCEPTION 'PROPOSAL_RERUN_TEST_FAILED: k3 er ikke v2-nøglen for version 2';
  END IF;
  RAISE NOTICE 'OK: test_key_v2_b_c_b';
END $t$;
COMMIT;

-- test_projection_follows_key_version (Task 13, R13-c; spec §4.4 pkt. 6): forslagsprojektionen genberegner hver nøgle
-- med den nøgle- og tekstversion, den skabende forslags-events kvittering bærer. B → C → B-posten (kilde -66901) har
-- v1-nøglen k1 (foreslået + forældet), v2/1-nøglen k2 (foreslået + forældet) og v2/2-nøglen k3: alle fem rækker skal
-- have key_matches, og key_material_sha256 skal være kvitteringens. Negativt: v1-nøglen genberegnet mod den reviderede
-- (gældende) tekst — v2 med den gældende tekstversion — er IKKE nøglen, og v1-genberegningen af en v2-nøgle heller ikke.
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL TimeZone = 'UTC';
SET LOCAL DateStyle = 'ISO, YMD';
SET LOCAL IntervalStyle = 'postgres';
SET LOCAL extra_float_digits = 1;
SET LOCAL bytea_output = 'hex';
SELECT set_config('daa.interpretation_projection_source_id','-66901',true) AS projection_source_id \gset
\ir ../../.claude/skills/daa-extract/scripts/interpretation_proposal_projection.sql
SELECT pg_temp.rr_assert_projection(:'projection'::jsonb,-66901);
\echo OK: test_projection_follows_key_version

ROLLBACK;
\echo PASS test-interpretation-proposal-rerun
