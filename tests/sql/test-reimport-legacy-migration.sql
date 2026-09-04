-- #166 149b: legacy-migration — læsefiltre, elementoperation, writer og reversal.
-- Forudsætning: basen er writer_1939 efter tests/sql/reimport-writer-v2-bootstrap.sql
-- (kontraktversion 2, syntetiske personer/records/bindinger, aktør med rolle redaktion).
-- Alle fixtures er syntetiske og opdigtede; filen kører i én transaktion og ruller altid tilbage.
\set ON_ERROR_STOP on
BEGIN;

DO $precondition$ BEGIN
  IF public.narrative_record_contract_version()<>2 THEN RAISE EXCEPTION 'TEST_REQUIRES_CONTRACT_V2'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE rolle='redaktion') THEN RAISE EXCEPTION 'TEST_FIXTURE_ACTOR_MISSING'; END IF;
END $precondition$;

-- Task 1: en migreret ledger-række må aldrig vises som legacy.
DO $task1_read_filter$
DECLARE
  v_person bigint; v_narrative bigint; v_source bigint := 149001; v_ref uuid := gen_random_uuid();
  v_actor uuid; v_state jsonb; v_sha text; v_rows integer;
  v_text text := 'Alfa T1 Bravo, f. 1801, d. 1860.';
BEGIN
  SELECT id INTO v_actor FROM public.profiles WHERE rolle='redaktion' ORDER BY id LIMIT 1;
  IF NOT EXISTS (SELECT 1 FROM public.change_set) THEN
    INSERT INTO public.change_set(actor_navn,actor_rolle,operation,summary,subjekt_synlighed)
    VALUES('fixture','system','fixture','fixture','offentlig');
  END IF;
  -- Selvstændig syntetisk fixture: uafhængig af hvad tidligere testtrin har bundet i basen.
  INSERT INTO public.source(id,titel,udgave,aar,slags)
  VALUES(v_source,'Fixture 149b T1','synthetic-t1',1900,'DAA-udgave') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.person(levende,privat,staged) VALUES(false,false,false) RETURNING id INTO v_person;
  INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst,privat)
  VALUES('person',v_person,v_source,'10',v_text,false) RETURNING id INTO v_narrative;

  v_state:=private.narrative_legacy_candidate_publication_state(v_narrative,v_source,v_ref);
  v_sha:=encode(extensions.digest(v_state::text,'sha256'),'hex');
  INSERT INTO private.narrative_legacy_publication(legacy_publication_ref,narrative_id,source_id,baseline_state,baseline_sha256,status)
  VALUES(v_ref,v_narrative,v_source,v_state,v_sha,'grandfathered_publication');
  INSERT INTO private.narrative_publication_event(change_set_id,stream_ref,stream_version,event_type,narrative_id,source_id,legacy_publication_ref,decision_basis,before_state,after_state,before_state_sha256,after_state_sha256,decided_by_name)
  VALUES((SELECT max(id) FROM public.change_set),v_ref,1,'baseline',v_narrative,v_source,v_ref,'test',v_state,v_state,v_sha,v_sha,'test');
  UPDATE private.narrative_legacy_publication SET latest_event_id=(SELECT id FROM private.narrative_publication_event WHERE stream_ref=v_ref) WHERE legacy_publication_ref=v_ref;

  SELECT count(*) INTO v_rows FROM public.public_person_bio_source_versions_v2(ARRAY[v_person]) r WHERE r.provenance_kind='legacy_narrative' AND r.source_id=v_source;
  IF v_rows<>1 THEN RAISE EXCEPTION 'TASK1_GRANDFATHERED_ROW_EXPECTED: %',v_rows; END IF;
  -- Sæt status til migrated uden at ændre baseline (triggeren tillader det).
  UPDATE private.narrative_legacy_publication SET status='migrated' WHERE legacy_publication_ref=v_ref;
  SELECT count(*) INTO v_rows FROM public.public_person_bio_source_versions_v2(ARRAY[v_person]) r WHERE r.provenance_kind='legacy_narrative' AND r.source_id=v_source;
  IF v_rows<>0 THEN RAISE EXCEPTION 'TASK1_MIGRATED_ROW_LEAKED_V2: %',v_rows; END IF;
  SELECT count(*) INTO v_rows FROM public.public_person_bio_source_versions(ARRAY[v_person]) r WHERE r.provenance_kind='legacy_narrative';
  IF v_rows<>0 THEN RAISE EXCEPTION 'TASK1_MIGRATED_ROW_LEAKED_V1: %',v_rows; END IF;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SELECT count(*) INTO v_rows FROM public.red_person_narrative_records(v_person) r WHERE r.provenance_kind='grandfathered_legacy' AND r.legacy_publication_ref=v_ref;
  IF v_rows<>0 THEN RAISE EXCEPTION 'TASK1_MIGRATED_ROW_LEAKED_EDITOR: %',v_rows; END IF;
  -- withdrawn skal fortsat vises i redaktørlisten (historik), men ikke offentligt.
  UPDATE private.narrative_legacy_publication SET status='withdrawn' WHERE legacy_publication_ref=v_ref;
  SELECT count(*) INTO v_rows FROM public.red_person_narrative_records(v_person) r WHERE r.provenance_kind='grandfathered_legacy' AND r.legacy_publication_ref=v_ref;
  IF v_rows<>1 THEN RAISE EXCEPTION 'TASK1_WITHDRAWN_ROW_HIDDEN_EDITOR: %',v_rows; END IF;
  SELECT count(*) INTO v_rows FROM public.public_person_bio_source_versions_v2(ARRAY[v_person]) r WHERE r.provenance_kind='legacy_narrative' AND r.source_id=v_source;
  IF v_rows<>0 THEN RAISE EXCEPTION 'TASK1_WITHDRAWN_ROW_LEAKED_V2: %',v_rows; END IF;
  RAISE NOTICE 'task1 read filter OK';
END $task1_read_filter$;

-- Task 2: elementoperationen legacy_migration i de lukkede mængder.
DO $task2_counts$
DECLARE v_err text; v_ok boolean:=false;
BEGIN
  -- (a) to-nøgle-manifest skal stadig valideres (149a-kompatibilitet)
  PERFORM private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":1}'::jsonb,
    jsonb_build_object('source-evidence:x','{}'::jsonb));
  -- (b) tre nøgler med legacy-migration-præfiks skal valideres
  BEGIN
    PERFORM private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"legacy_migrations":1}'::jsonb,
      jsonb_build_object('legacy-migration:x','{}'::jsonb));
    v_ok:=true;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK2_THREE_KEY_REJECTED: %',v_err; END IF;
  -- (c) forkert nøgle afvises fortsat
  v_ok:=false;
  BEGIN
    PERFORM private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"canonical_delta":0}'::jsonb,'{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK2_UNKNOWN_KEY_ACCEPTED'; END IF;
  -- (d) præfiks/antal-mismatch afvises
  v_ok:=false;
  BEGIN
    PERFORM private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"legacy_migrations":1}'::jsonb,
      jsonb_build_object('source-evidence:x','{}'::jsonb));
  EXCEPTION WHEN OTHERS THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK2_PREFIX_MISMATCH_ACCEPTED'; END IF;
  -- (e) CHECK-constraint accepterer den nye operation
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='private.reimport_event'::regclass AND contype='c'
                 AND pg_get_constraintdef(oid) LIKE '%legacy_migration%') THEN
    RAISE EXCEPTION 'TASK2_OPERATION_CHECK_MISSING';
  END IF;
  RAISE NOTICE 'task2 counts OK';
END $task2_counts$;

-- Task 3: writeren private.migrate_legacy_narrative_record og dens offentlige RPC.
-- Hjælper: opret en fuld 149b-fixture og returnér nøglerne. Alt syntetisk.
CREATE FUNCTION pg_temp.task3_fixture(p_key text, p_levende boolean)
RETURNS jsonb LANGUAGE plpgsql AS $fixture$
DECLARE
  -- Egen syntetisk source + profil pr. fixture: undgår REIMPORT_WRITER_RENDITION_DRIFT
  -- mod basens eksisterende rendition og REPLAY_DRIFT på genbrugte manifest-hashes.
  v_source bigint := 149100 + abs(hashtext(p_key)) % 100000; v_profile text := 'fixture-lm-'||p_key; v_sha text;
  v_config jsonb; v_actor uuid; v_person bigint; v_narrative bigint;
  v_text text := 'Alfa '||p_key||' Bravo, f. 1801, d. 1860.';
  v_msha text := encode(extensions.digest('manifest:'||p_key,'sha256'),'hex');
  v_psha text := encode(extensions.digest('preview:'||p_key,'sha256'),'hex');
  v_auth uuid; v_batch uuid; v_payload jsonb; v_ref uuid := gen_random_uuid(); v_state jsonb; v_baseline text;
BEGIN
  INSERT INTO public.source(id,titel,udgave,aar,slags) VALUES(v_source,'Fixture '||p_key,'synthetic','1900','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  v_config:=jsonb_build_object('citation_label_template','Synthetic side {page_from}','extractor_version','fixture-v1',
    'observation_extraction_method','deterministic_segment_v1','rendition_key','fixture-r1','rendition_kind','pdf_text_layer',
    'rendition_metadata',jsonb_build_object('edition','fixture','pdf_sha256',repeat('a',64),'pdftotext_version','fixture 0.0'),
    'run_key_prefix','reimport-source-evidence:','schema_version','source-evidence-manifest-v1');
  v_sha:=private.reimport_canonical_json_sha256(v_config);
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES(v_source,v_profile,'source-evidence-v1',v_sha,v_config) ON CONFLICT DO NOTHING;
  SELECT id INTO v_actor FROM public.profiles WHERE rolle='redaktion' ORDER BY id LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  IF NOT EXISTS (SELECT 1 FROM public.change_set) THEN
    INSERT INTO public.change_set(actor_navn,actor_rolle,operation,summary,subjekt_synlighed) VALUES('fixture','system','fixture','fixture','offentlig');
  END IF;
  -- visning_navn er en cache-kolonne (invariant 4): skrives aldrig direkte.
  INSERT INTO public.person(levende,privat,staged,visning_navn) VALUES(p_levende,false,false,NULL) RETURNING id INTO v_person;
  INSERT INTO public.person_external_id(person_id,source_id,record_key) VALUES(v_person,v_source,p_key);
  INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst,privat) VALUES('person',v_person,v_source,'10',v_text,false) RETURNING id INTO v_narrative;
  -- 149a-ækvivalent: source record + forekomst + anker + observation + mention
  v_payload:=jsonb_build_object('source_record_key',p_key,'source_id',v_source,'category','person_post',
    'disposition','retain_source_only','rendition_content_sha256',repeat('c',64),
    'source_span',jsonb_build_object('char_from',0,'char_to',length(v_text)),
    'page_evidence',jsonb_build_object('page_from',10,'page_to',10),
    'verbatim_text',v_text,'verbatim_sha256',encode(extensions.digest(v_text,'sha256'),'hex'),
    'anchor_method','deterministic-segment','segment_version','fixture');
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(v_msha,v_psha,
    jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    v_source,v_profile,v_sha,'{"person_creates":0,"source_evidence":1}'::jsonb,
    jsonb_build_object('source-evidence:'||p_key,v_payload),gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch:=public.red_begin_reimport(v_auth,v_msha,v_psha);
  PERFORM public.red_apply_reimport_source_evidence(v_batch,'source-evidence:'||p_key,v_payload);
  PERFORM public.red_finalize_reimport(v_batch);
  RESET role;
  IF NOT p_levende THEN
    v_state:=private.narrative_legacy_candidate_publication_state(v_narrative,v_source,v_ref);
    v_baseline:=encode(extensions.digest(v_state::text,'sha256'),'hex');
    INSERT INTO private.narrative_legacy_publication(legacy_publication_ref,narrative_id,source_id,baseline_state,baseline_sha256,status)
    VALUES(v_ref,v_narrative,v_source,v_state,v_baseline,'grandfathered_publication');
    INSERT INTO private.narrative_publication_event(change_set_id,stream_ref,stream_version,event_type,narrative_id,source_id,legacy_publication_ref,decision_basis,before_state,after_state,before_state_sha256,after_state_sha256,decided_by_name)
    VALUES((SELECT max(id) FROM public.change_set),v_ref,1,'baseline',v_narrative,v_source,v_ref,'fixture',v_state,v_state,v_baseline,v_baseline,'fixture');
    UPDATE private.narrative_legacy_publication SET latest_event_id=(SELECT id FROM private.narrative_publication_event WHERE stream_ref=v_ref) WHERE legacy_publication_ref=v_ref;
  END IF;
  RETURN jsonb_build_object('source_id',v_source,'profile_id',v_profile,'profile_sha256',v_sha,'actor',v_actor,
    'person_id',v_person,'narrative_id',v_narrative,'record_key',p_key,
    'narrative_text_sha256',encode(extensions.digest(v_text,'sha256'),'hex'),
    'occurrence_verbatim_sha256',encode(extensions.digest(v_text,'sha256'),'hex'),
    'legacy_publication_ref',CASE WHEN p_levende THEN NULL ELSE v_ref END,
    'legacy_baseline_sha256',CASE WHEN p_levende THEN NULL ELSE v_baseline END);
END $fixture$;

-- Hjælper: byg 149b-payloaden (lukket 11-nøglemængde) for en fixture.
CREATE FUNCTION pg_temp.task3_payload(p_fx jsonb, p_disposition text)
RETURNS jsonb LANGUAGE sql AS $payload$
  SELECT jsonb_build_object(
    'source_record_key',p_fx->>'record_key','source_id',(p_fx->>'source_id')::bigint,
    'person_id',(p_fx->>'person_id')::bigint,'narrative_id',(p_fx->>'narrative_id')::bigint,
    'disposition',p_disposition,
    'narrative_text_sha256',p_fx->>'narrative_text_sha256',
    'occurrence_verbatim_sha256',p_fx->>'occurrence_verbatim_sha256',
    'normalized_text_sha256',p_fx->>'narrative_text_sha256',
    'legacy_publication_ref',p_fx->'legacy_publication_ref',
    'legacy_baseline_sha256',p_fx->'legacy_baseline_sha256',
    'persona_key',p_fx->>'record_key')
$payload$;

-- Hjælper: kør én legacy-migration-batch med præcis ét element og en vilkårlig
-- payload/elementnøgle. Autorisationen hash-binder payloaden, så mutationer skal
-- gå gennem denne vej og ikke gennem en efterfølgende ændring.
CREATE FUNCTION pg_temp.task3_migrate_raw(p_fx jsonb, p_payload jsonb, p_element_key text, p_manifest_nonce text)
RETURNS jsonb LANGUAGE plpgsql AS $raw$
DECLARE v_auth uuid; v_batch uuid; v_result jsonb; v_msha text := encode(extensions.digest(p_manifest_nonce,'sha256'),'hex');
  v_lm_profile text := (p_fx->>'profile_id')||'-lm'; v_lm_config jsonb; v_lm_sha text;
BEGIN
  -- Legacy-migration-profil for fixturens source (spec 6.1: egen profil, samme lukkede feltmængde).
  v_lm_config:=jsonb_build_object('citation_label_template','Synthetic side {page_from}','extractor_version','legacy-migration-v1',
    'observation_extraction_method','none','rendition_key','fixture-r1','rendition_kind','pdf_text_layer',
    'rendition_metadata',jsonb_build_object('edition','fixture','pdf_sha256',repeat('a',64),'pdftotext_version','fixture 0.0'),
    'run_key_prefix','reimport-legacy-migration:','schema_version','legacy-migration-manifest-v1');
  v_lm_sha:=private.reimport_canonical_json_sha256(v_lm_config);
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES((p_fx->>'source_id')::bigint,v_lm_profile,'legacy-migration-v1',v_lm_sha,v_lm_config) ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub',p_fx->>'actor',true);
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(v_msha,repeat('9',64),
    jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    (p_fx->>'source_id')::bigint,v_lm_profile,v_lm_sha,
    '{"person_creates":0,"source_evidence":0,"legacy_migrations":1}'::jsonb,
    jsonb_build_object('legacy-migration:'||p_element_key,p_payload),gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch:=public.red_begin_reimport(v_auth,v_msha,repeat('9',64));
  v_result:=public.red_apply_reimport_legacy_migration(v_batch,'legacy-migration:'||p_element_key,p_payload);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_finalize_reimport(v_batch);
  RESET role;
  RETURN v_result||jsonb_build_object('batch_id',v_batch,'authorization_id',v_auth);
END $raw$;

-- Hjælper: den almindelige vej — kanonisk payload for fixturen.
CREATE FUNCTION pg_temp.task3_migrate(p_fx jsonb, p_disposition text, p_manifest_nonce text)
RETURNS jsonb LANGUAGE plpgsql AS $migrate$
BEGIN
  RETURN pg_temp.task3_migrate_raw(p_fx,pg_temp.task3_payload(p_fx,p_disposition),p_fx->>'record_key',p_manifest_nonce);
END $migrate$;

DO $task3_happy_path$
DECLARE fx jsonb; r jsonb; v_rows integer; v_status text; v_kind text;
BEGIN
  -- bound_published
  fx:=pg_temp.task3_fixture('T3P',false);
  r:=pg_temp.task3_migrate(fx,'bound_published','t3p');
  SELECT status INTO v_status FROM private.narrative_legacy_publication WHERE legacy_publication_ref=(fx->>'legacy_publication_ref')::uuid;
  IF v_status<>'migrated' THEN RAISE EXCEPTION 'TASK3_LEDGER_NOT_MIGRATED: %',v_status; END IF;
  SELECT status INTO v_status FROM private.narrative_record_publication WHERE id=(r->>'binding_id')::uuid;
  IF v_status<>'published' THEN RAISE EXCEPTION 'TASK3_BINDING_NOT_PUBLISHED: %',v_status; END IF;
  SELECT count(*) INTO v_rows FROM private.narrative_publication_event WHERE narrative_id=(fx->>'narrative_id')::bigint AND event_type IN ('legacy_migrated','draft_created','published');
  IF v_rows<>3 THEN RAISE EXCEPTION 'TASK3_EVENT_COUNT: %',v_rows; END IF;
  IF NOT public.person_daa_narrative_publication_allowed((fx->>'narrative_id')::bigint) THEN RAISE EXCEPTION 'TASK3_GATE_CLOSED'; END IF;
  SELECT count(*) INTO v_rows FROM public.public_person_bio_source_versions_v2(ARRAY[(fx->>'person_id')::bigint]);
  IF v_rows<>1 THEN RAISE EXCEPTION 'TASK3_PUBLIC_ROWS: % (forventet praecis 1, ingen dublet)',v_rows; END IF;
  SELECT provenance_kind INTO v_kind FROM public.public_person_bio_source_versions_v2(ARRAY[(fx->>'person_id')::bigint]);
  IF v_kind<>'source_record' THEN RAISE EXCEPTION 'TASK3_PUBLIC_KIND: %',v_kind; END IF;
  SELECT count(*) INTO v_rows FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
   WHERE p.persona_key='T3P' AND i.decision_status='accepted' AND i.canonical_person_id=(fx->>'person_id')::bigint AND i.evidence->>'authority'='person_external_id';
  IF v_rows<>1 THEN RAISE EXCEPTION 'TASK3_IDENTITY_LEDGER: %',v_rows; END IF;
  SELECT count(*) INTO v_rows FROM private.reimport_event WHERE batch_id=(r->>'batch_id')::uuid AND operation='legacy_migration';
  IF v_rows<>1 THEN RAISE EXCEPTION 'TASK3_REIMPORT_EVENT: %',v_rows; END IF;
  -- narrativraekken er uroert
  IF (SELECT encode(extensions.digest(tekst,'sha256'),'hex') FROM public.narrative WHERE id=(fx->>'narrative_id')::bigint)<>fx->>'narrative_text_sha256' THEN RAISE EXCEPTION 'TASK3_TEXT_CHANGED'; END IF;
  -- bound_draft (levende)
  fx:=pg_temp.task3_fixture('T3D',true);
  r:=pg_temp.task3_migrate(fx,'bound_draft','t3d');
  SELECT status INTO v_status FROM private.narrative_record_publication WHERE id=(r->>'binding_id')::uuid;
  IF v_status<>'draft' THEN RAISE EXCEPTION 'TASK3_DRAFT_STATUS: %',v_status; END IF;
  IF (r->'published_event_id') IS DISTINCT FROM 'null'::jsonb OR (r->'legacy_event_id') IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'TASK3_DRAFT_EXTRA_EVENTS'; END IF;
  IF public.person_daa_narrative_publication_allowed((fx->>'narrative_id')::bigint) THEN RAISE EXCEPTION 'TASK3_DRAFT_PUBLIC'; END IF;
  SELECT count(*) INTO v_rows FROM public.public_person_bio_source_versions_v2(ARRAY[(fx->>'person_id')::bigint]);
  IF v_rows<>0 THEN RAISE EXCEPTION 'TASK3_DRAFT_PUBLIC_ROWS: %',v_rows; END IF;
  RAISE NOTICE 'task3 happy path OK';
END $task3_happy_path$;

-- Spec §10: replay = already_applied, begge offentlige funktioner + redaktørlisten
-- efter en ÆGTE migration, og narrativrækken bit-for-bit urørt (§6.5).
DO $task3_reads_and_replay$
DECLARE
  fx jsonb; r jsonb; v_rows integer; v_kind text; v_status text;
  v_tekst_før text; v_privat_før boolean; v_side_før text;
  v_tekst_efter text; v_privat_efter boolean; v_side_efter text;
  v_events_før integer; v_events_efter integer;
  v_lm_profile text; v_lm_sha text; v_payload jsonb;
  v_msha text := encode(extensions.digest('t3x','sha256'),'hex');
  v_auth uuid; v_batch2 uuid; v_res jsonb; v_ok boolean; v_err text;
BEGIN
  fx:=pg_temp.task3_fixture('T3X',false);
  SELECT tekst,coalesce(privat,false),side INTO v_tekst_før,v_privat_før,v_side_før
    FROM public.narrative WHERE id=(fx->>'narrative_id')::bigint;
  r:=pg_temp.task3_migrate(fx,'bound_published','t3x');

  -- (iii) narrativrækken er urørt: tekst, privat OG side
  SELECT tekst,coalesce(privat,false),side INTO v_tekst_efter,v_privat_efter,v_side_efter
    FROM public.narrative WHERE id=(fx->>'narrative_id')::bigint;
  IF v_tekst_efter IS DISTINCT FROM v_tekst_før THEN RAISE EXCEPTION 'TASK3X_NARRATIVE_TEKST_CHANGED'; END IF;
  IF v_privat_efter IS DISTINCT FROM v_privat_før THEN RAISE EXCEPTION 'TASK3X_NARRATIVE_PRIVAT_CHANGED'; END IF;
  IF v_side_efter IS DISTINCT FROM v_side_før THEN RAISE EXCEPTION 'TASK3X_NARRATIVE_SIDE_CHANGED'; END IF;

  -- (ii) redaktørlisten: præcis én række, source_record, published, ingen grandfathered_legacy
  PERFORM set_config('request.jwt.claim.sub',fx->>'actor',true);
  SELECT count(*) INTO v_rows FROM public.red_person_narrative_records((fx->>'person_id')::bigint);
  IF v_rows<>1 THEN RAISE EXCEPTION 'TASK3X_EDITOR_ROWS: %',v_rows; END IF;
  SELECT provenance_kind,publication_status INTO v_kind,v_status
    FROM public.red_person_narrative_records((fx->>'person_id')::bigint);
  IF v_kind<>'source_record' OR v_status<>'published' THEN RAISE EXCEPTION 'TASK3X_EDITOR_ROW: % %',v_kind,v_status; END IF;
  SELECT count(*) INTO v_rows FROM public.red_person_narrative_records((fx->>'person_id')::bigint) WHERE provenance_kind='grandfathered_legacy';
  IF v_rows<>0 THEN RAISE EXCEPTION 'TASK3X_EDITOR_LEGACY_LEAK: %',v_rows; END IF;

  -- (ii) v1-navnet: præcis én række, source_record
  SELECT count(*) INTO v_rows FROM public.public_person_bio_source_versions(ARRAY[(fx->>'person_id')::bigint]);
  IF v_rows<>1 THEN RAISE EXCEPTION 'TASK3X_PUBLIC_V1_ROWS: %',v_rows; END IF;
  SELECT provenance_kind INTO v_kind FROM public.public_person_bio_source_versions(ARRAY[(fx->>'person_id')::bigint]);
  IF v_kind<>'source_record' THEN RAISE EXCEPTION 'TASK3X_PUBLIC_V1_KIND: %',v_kind; END IF;

  -- (i) replay: samme manifest/preview/profil/elementer -> samme finaliserede batch,
  -- already_applied-vejen, og ingen nye events.
  SELECT count(*) INTO v_events_før FROM private.narrative_publication_event WHERE narrative_id=(fx->>'narrative_id')::bigint;
  v_lm_profile:=(fx->>'profile_id')||'-lm';
  SELECT profile_sha256 INTO v_lm_sha FROM private.reimport_writer_profile
   WHERE source_id=(fx->>'source_id')::bigint AND profile_id=v_lm_profile;
  v_payload:=pg_temp.task3_payload(fx,'bound_published');
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(v_msha,repeat('9',64),
    jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    (fx->>'source_id')::bigint,v_lm_profile,v_lm_sha,
    '{"person_creates":0,"source_evidence":0,"legacy_migrations":1}'::jsonb,
    jsonb_build_object('legacy-migration:'||(fx->>'record_key'),v_payload),gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch2:=public.red_begin_reimport(v_auth,v_msha,repeat('9',64));
  v_res:=public.red_reimport_batch_result(v_auth,v_batch2);
  RESET role;
  IF v_batch2::text IS DISTINCT FROM r->>'batch_id' THEN RAISE EXCEPTION 'TASK3X_REPLAY_NEW_BATCH: % vs %',v_batch2,r->>'batch_id'; END IF;
  IF v_res->>'status'<>'finalized' OR (v_res->>'replayed')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'TASK3X_REPLAY_RESULT: %',v_res; END IF;
  SELECT count(*) INTO v_events_efter FROM private.narrative_publication_event WHERE narrative_id=(fx->>'narrative_id')::bigint;
  IF v_events_efter<>v_events_før THEN RAISE EXCEPTION 'TASK3X_REPLAY_WROTE_EVENTS: % -> %',v_events_før,v_events_efter; END IF;
  SELECT count(*) INTO v_rows FROM private.reimport_event WHERE batch_id=v_batch2 AND operation='legacy_migration';
  IF v_rows<>1 THEN RAISE EXCEPTION 'TASK3X_REPLAY_REIMPORT_EVENTS: %',v_rows; END IF;

  -- Spec §8: batch-reversal af en ren legacy_migration-batch afvises fail-closed,
  -- og hverken ledger, binding eller batch må ændre sig.
  PERFORM set_config('request.jwt.claim.sub',fx->>'actor',true);
  v_ok:=false;
  BEGIN
    v_auth:=public.red_authorize_reimport_reversal((r->>'batch_id')::uuid,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
    PERFORM public.red_reverse_reimport((r->>'batch_id')::uuid,v_auth);
  EXCEPTION WHEN OTHERS THEN v_ok:=SQLERRM LIKE 'REIMPORT_WRITER_REVERSAL_INVALID%'; v_err:=SQLERRM; END;
  PERFORM set_config('app.change_set_id','',true);
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK3X_BATCH_REVERSAL_ACCEPTED got %',coalesce(v_err,'(success)'); END IF;
  SELECT status INTO v_status FROM private.narrative_legacy_publication WHERE legacy_publication_ref=(fx->>'legacy_publication_ref')::uuid;
  IF v_status<>'migrated' THEN RAISE EXCEPTION 'TASK3X_BATCH_REVERSAL_TOUCHED_LEDGER: %',v_status; END IF;
  SELECT status INTO v_status FROM private.narrative_record_publication WHERE narrative_id=(fx->>'narrative_id')::bigint;
  IF v_status<>'published' THEN RAISE EXCEPTION 'TASK3X_BATCH_REVERSAL_TOUCHED_BINDING: %',v_status; END IF;
  SELECT status INTO v_status FROM private.reimport_batch WHERE id=(r->>'batch_id')::uuid;
  IF v_status<>'finalized' THEN RAISE EXCEPTION 'TASK3X_BATCH_REVERSAL_TOUCHED_BATCH: %',v_status; END IF;
  RAISE NOTICE 'task3 reads and replay OK';
END $task3_reads_and_replay$;

-- Hjælper: forvent en bestemt fejlkode fra én migration (subtransaktion ruller tilbage).
CREATE FUNCTION pg_temp.task3_expect(p_code text, p_fx jsonb, p_disposition text, p_nonce text)
RETURNS void LANGUAGE plpgsql AS $expect$
BEGIN
  BEGIN
    PERFORM pg_temp.task3_migrate(p_fx,p_disposition,p_nonce);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE p_code||'%' THEN RETURN; END IF;
    RAISE EXCEPTION 'TASK3_EXPECTED_% GOT %',p_code,SQLERRM;
  END;
  RAISE EXCEPTION 'TASK3_EXPECTED_%_BUT_SUCCEEDED',p_code;
END $expect$;

DO $task3_rejections$
DECLARE fx jsonb; v_ok boolean;
BEGIN
  -- (1) publicerbar person uden ledger-raekke -> LEDGER_INCONSISTENT
  fx:=pg_temp.task3_fixture('T3R1',true);
  UPDATE public.person SET levende=false WHERE id=(fx->>'person_id')::bigint;
  PERFORM pg_temp.task3_expect('LEGACY_MIGRATION_LEDGER_INCONSISTENT',fx,'bound_draft','t3r1');
  -- (2) bound_published med ledger-status withdrawn
  fx:=pg_temp.task3_fixture('T3R2',false);
  UPDATE private.narrative_legacy_publication SET status='withdrawn' WHERE legacy_publication_ref=(fx->>'legacy_publication_ref')::uuid;
  PERFORM pg_temp.task3_expect('LEGACY_MIGRATION_LEDGER_INCONSISTENT',fx,'bound_published','t3r2');
  -- (3) tekstdrift i narrativet
  fx:=pg_temp.task3_fixture('T3R3',false);
  UPDATE public.narrative SET tekst=tekst||' x' WHERE id=(fx->>'narrative_id')::bigint;
  PERFORM pg_temp.task3_expect('LEGACY_MIGRATION_NARRATIVE_TEXT_DRIFT',fx,'bound_published','t3r3');
  -- (4) identitet: external_id fjernet -> tvetydig
  fx:=pg_temp.task3_fixture('T3R4',false);
  DELETE FROM public.person_external_id WHERE person_id=(fx->>'person_id')::bigint;
  PERFORM pg_temp.task3_expect('LEGACY_MIGRATION_IDENTITY_AMBIGUOUS',fx,'bound_published','t3r4');
  -- (5) allerede bundet: anden batch (nyt manifest-nonce) mod samme narrativ
  fx:=pg_temp.task3_fixture('T3R5',false);
  PERFORM pg_temp.task3_migrate(fx,'bound_published','t3r5');
  PERFORM pg_temp.task3_expect('LEGACY_MIGRATION_ALREADY_BOUND',fx,'bound_published','t3r5b');
  -- (6) ikke-autoriseret element/ukendt batch afvises af writer-gaten
  v_ok:=false;
  BEGIN
    PERFORM public.red_apply_reimport_legacy_migration(gen_random_uuid(),'legacy-migration:T3R6','{"x":1}'::jsonb);
  EXCEPTION WHEN OTHERS THEN v_ok:=SQLERRM LIKE 'REIMPORT_WRITER_%'; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK3_EXPECTED_WRITER_GATE'; END IF;
  RAISE NOTICE 'task3 rejections OK';
END $task3_rejections$;

-- Hjælper: forvent en bestemt fejlkode fra én migration med vilkårlig payload.
CREATE FUNCTION pg_temp.task3_expect_raw(p_code text, p_fx jsonb, p_payload jsonb, p_element_key text, p_nonce text)
RETURNS void LANGUAGE plpgsql AS $expectraw$
BEGIN
  BEGIN
    PERFORM pg_temp.task3_migrate_raw(p_fx,p_payload,p_element_key,p_nonce);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE p_code||'%' THEN RETURN; END IF;
    RAISE EXCEPTION 'TASK3P_EXPECTED_% GOT %',p_code,SQLERRM;
  END;
  RAISE EXCEPTION 'TASK3P_EXPECTED_%_BUT_SUCCEEDED',p_code;
END $expectraw$;

-- Spec §10: ALLE §6.3-preconditions skal fejle med deres egen kode.
DO $task3_preconditions$
DECLARE
  fx jsonb; fx2 jsonb; p jsonb; v_person bigint; v_narrative bigint; v_occ uuid; v_obs uuid; v_run uuid; v_cs text;
BEGIN
  -- ---- LEGACY_MIGRATION_PAYLOAD_INVALID (fem former) ----
  fx:=pg_temp.task3_fixture('P1',false);
  p:=pg_temp.task3_payload(fx,'bound_published');
  -- (1) ekstra nøgle
  PERFORM pg_temp.task3_expect_raw('LEGACY_MIGRATION_PAYLOAD_INVALID',fx,p||'{"extra_key":1}'::jsonb,fx->>'record_key','p1a');
  -- (2) manglende nøgle
  PERFORM pg_temp.task3_expect_raw('LEGACY_MIGRATION_PAYLOAD_INVALID',fx,p-'persona_key',fx->>'record_key','p1b');
  -- (3) ukendt disposition
  PERFORM pg_temp.task3_expect_raw('LEGACY_MIGRATION_PAYLOAD_INVALID',fx,jsonb_set(p,'{disposition}','"bound_elsewhere"'),fx->>'record_key','p1c');
  -- (4) bound_published uden legacy_publication_ref
  PERFORM pg_temp.task3_expect_raw('LEGACY_MIGRATION_PAYLOAD_INVALID',fx,jsonb_set(p,'{legacy_publication_ref}','null'),fx->>'record_key','p1d');
  -- (5) bound_draft MED legacy_publication_ref/baseline
  PERFORM pg_temp.task3_expect_raw('LEGACY_MIGRATION_PAYLOAD_INVALID',fx,jsonb_set(p,'{disposition}','"bound_draft"'),fx->>'record_key','p1e');
  -- (6) forkert hash-format
  PERFORM pg_temp.task3_expect_raw('LEGACY_MIGRATION_PAYLOAD_INVALID',fx,jsonb_set(p,'{normalized_text_sha256}','"ikke-en-hash"'),fx->>'record_key','p1f');

  -- ---- NARRATIVE_RECORD_FOREIGN_CHANGE_SET ----
  v_cs:=(SELECT max(id)::text FROM public.change_set);
  PERFORM set_config('app.change_set_id',v_cs,true);
  BEGIN
    PERFORM pg_temp.task3_expect_raw('NARRATIVE_RECORD_FOREIGN_CHANGE_SET',fx,p,fx->>'record_key','p1g');
  EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.change_set_id','',true); RAISE; END;
  PERFORM set_config('app.change_set_id','',true);

  -- ---- LEGACY_MIGRATION_RECORD_MISSING ----
  PERFORM pg_temp.task3_expect_raw('LEGACY_MIGRATION_RECORD_MISSING',fx,
    jsonb_set(p,'{source_record_key}','"P1-FINDES-IKKE"'),'P1-FINDES-IKKE','p2');

  -- ---- LEGACY_MIGRATION_OCCURRENCE_TEXT_DRIFT ----
  PERFORM pg_temp.task3_expect_raw('LEGACY_MIGRATION_OCCURRENCE_TEXT_DRIFT',fx,
    jsonb_set(p,'{occurrence_verbatim_sha256}',to_jsonb(repeat('b',64))),fx->>'record_key','p3');

  -- ---- LEGACY_MIGRATION_ANCHOR_AMBIGUOUS (to accepterede ankre) ----
  fx:=pg_temp.task3_fixture('P4',false);
  SELECT o.id,o.rendition_id,o.extraction_run_id INTO v_occ,v_obs,v_run
    FROM private.source_record_anchor_current a
    JOIN private.source_record_occurrence o ON o.id=a.occurrence_id
    JOIN private.source_record r ON r.id=a.source_record_id
   WHERE r.source_id=(fx->>'source_id')::bigint AND r.record_key=fx->>'record_key';
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  SELECT o.rendition_id,'dublet:'||(fx->>'record_key'),o.page_from,o.page_to,o.char_from,o.char_to,o.verbatim_text,o.physical_fingerprint,o.structural_fingerprint,o.extraction_run_id
    FROM private.source_record_occurrence o WHERE o.id=v_occ
  RETURNING id INTO v_occ;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
  SELECT v_occ,r.id,'accepted',jsonb_build_object('fixture','anchor-ambiguous'),1,(fx->>'actor')::uuid,'fixture'
    FROM private.source_record r WHERE r.source_id=(fx->>'source_id')::bigint AND r.record_key=fx->>'record_key';
  PERFORM pg_temp.task3_expect('LEGACY_MIGRATION_ANCHOR_AMBIGUOUS',fx,'bound_published','p4');

  -- ---- LEGACY_MIGRATION_MENTION_AMBIGUOUS (to mentions på samme observation) ----
  fx:=pg_temp.task3_fixture('P5',false);
  SELECT ob.id,ob.extraction_run_id INTO v_obs,v_run
    FROM private.source_record_anchor_current a
    JOIN private.source_observation ob ON ob.occurrence_id=a.occurrence_id
    JOIN private.source_record r ON r.id=a.source_record_id
   WHERE r.source_id=(fx->>'source_id')::bigint AND r.record_key=fx->>'record_key';
  INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
  SELECT m.observation_id,m.mention_kind,m.char_from,m.char_to,m.verbatim_text,m.created_run_id
    FROM private.source_mention m WHERE m.observation_id=v_obs LIMIT 1;
  PERFORM pg_temp.task3_expect('LEGACY_MIGRATION_MENTION_AMBIGUOUS',fx,'bound_published','p5');

  -- ---- LEGACY_MIGRATION_NARRATIVE_AMBIGUOUS: to narrativer for samme person/source ----
  fx:=pg_temp.task3_fixture('P6',false);
  INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst,privat)
  VALUES('person',(fx->>'person_id')::bigint,(fx->>'source_id')::bigint,'11','Alfa P6 ekstra Bravo.',false);
  PERFORM pg_temp.task3_expect('LEGACY_MIGRATION_NARRATIVE_AMBIGUOUS',fx,'bound_published','p6');

  -- ---- LEGACY_MIGRATION_NARRATIVE_AMBIGUOUS: narrative_id peger et andet sted hen ----
  fx:=pg_temp.task3_fixture('P7',false);
  fx2:=pg_temp.task3_fixture('P7B',false);
  PERFORM pg_temp.task3_expect_raw('LEGACY_MIGRATION_NARRATIVE_AMBIGUOUS',fx,
    jsonb_set(pg_temp.task3_payload(fx,'bound_published'),'{narrative_id}',to_jsonb((fx2->>'narrative_id')::bigint)),
    fx->>'record_key','p7');

  -- ---- NARRATIVE_LEGACY_BASELINE_DRIFT (baseline er immutabel; kandidattilstanden driver) ----
  fx:=pg_temp.task3_fixture('P8',false);
  UPDATE public.narrative SET side='99' WHERE id=(fx->>'narrative_id')::bigint;
  PERFORM pg_temp.task3_expect('NARRATIVE_LEGACY_BASELINE_DRIFT',fx,'bound_published','p8');

  -- ---- LEGACY_MIGRATION_PERSONA_EXISTS ----
  fx:=pg_temp.task3_fixture('P9',false);
  SELECT id INTO v_run FROM private.extraction_run WHERE source_id=(fx->>'source_id')::bigint ORDER BY id LIMIT 1;
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id)
  VALUES((fx->>'source_id')::bigint,fx->>'record_key',v_run);
  PERFORM pg_temp.task3_expect('LEGACY_MIGRATION_PERSONA_EXISTS',fx,'bound_published','p9');

  -- ---- LEGACY_MIGRATION_PRESTATE_INVALID (aktiv binding fra et andet narrativ på samme record) ----
  fx:=pg_temp.task3_fixture('P10',false);
  INSERT INTO public.person(levende,privat,staged) VALUES(false,false,false) RETURNING id INTO v_person;
  INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst,privat)
  VALUES('person',v_person,(fx->>'source_id')::bigint,'12','Alfa P10 anden Bravo.',false) RETURNING id INTO v_narrative;
  INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status)
  SELECT v_narrative,r.id,'fixture-label','fixture-citation','draft'
    FROM private.source_record r WHERE r.source_id=(fx->>'source_id')::bigint AND r.record_key=fx->>'record_key';
  PERFORM pg_temp.task3_expect('LEGACY_MIGRATION_PRESTATE_INVALID',fx,'bound_published','p10');

  RAISE NOTICE 'task3 preconditions OK';
END $task3_preconditions$;

-- Task 4: legacy_migrated-grenen i den dedikerede reversal.
-- Bemærk: rollen skiftes ikke i denne blok. private.narrative_legacy_state og
-- private.narrative_record_state er revoked for authenticated, og testen måler
-- reversal-semantik, ikke RPC-ACL (den dækkes af Task 5's inventar).
DO $task4_reversal$
DECLARE fx jsonb; r jsonb; v_state jsonb; v_res jsonb; v_status text; v_err text; v_ok boolean;
  v_can_reverse boolean; v_block text;
BEGIN
  fx:=pg_temp.task3_fixture('T4',false);
  r:=pg_temp.task3_migrate(fx,'bound_published','t4');
  PERFORM set_config('request.jwt.claim.sub',fx->>'actor',true);
  -- (a) legacy_migrated kan ikke fortrydes, mens bindingen er aktiv
  v_state:=private.narrative_legacy_state((fx->>'legacy_publication_ref')::uuid,false);
  v_ok:=false;
  BEGIN
    PERFORM public.red_fortryd_person_narrative_publication_event((r->>'legacy_event_id')::uuid,v_state->>'state_sha256');
  EXCEPTION WHEN OTHERS THEN v_ok:=SQLERRM LIKE 'NARRATIVE_LEGACY_MIGRATION_BINDING_ACTIVE%'; v_err:=SQLERRM; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK4_EXPECTED_BINDING_ACTIVE got %',v_err; END IF;
  -- I-1: redaktørfladens historik skal sige det samme som RPC'en — blokeret nu ...
  SELECT can_reverse,blocking_reason INTO v_can_reverse,v_block
    FROM public.red_person_narrative_publication_history((fx->>'person_id')::bigint)
   WHERE event_type='legacy_migrated';
  IF v_can_reverse IS NOT FALSE OR v_block IS DISTINCT FROM 'NARRATIVE_LEGACY_MIGRATION_BINDING_ACTIVE' THEN
    RAISE EXCEPTION 'TASK4_HISTORY_ACTIVE_BINDING: % %',v_can_reverse,v_block;
  END IF;
  -- (b) published -> draft
  v_state:=private.narrative_record_state((fx->>'person_id')::bigint,(fx->>'source_id')::bigint,fx->>'record_key',false);
  v_res:=public.red_fortryd_person_narrative_publication_event((r->>'published_event_id')::uuid,v_state->>'state_sha256');
  PERFORM set_config('app.change_set_id','',true);
  IF v_res->>'status'<>'draft' THEN RAISE EXCEPTION 'TASK4_STEP_B: %',v_res->>'status'; END IF;
  -- (c) draft -> withdrawn. Fortrydelse af selve draft_created-eventet er umulig her:
  -- reversal af published har appendet et reversal-event, så draft_created ikke længere
  -- er streamens seneste (#152: NARRATIVE_PUBLICATION_EVENT_NOT_LATEST). Den reelle
  -- redaktørvej til en inaktiv binding er discard_draft; spec §8's gate kræver netop
  -- kun, at bindingen ikke er aktiv.
  v_state:=private.narrative_record_state((fx->>'person_id')::bigint,(fx->>'source_id')::bigint,fx->>'record_key',false);
  v_res:=public.red_kasser_person_narrative_record((fx->>'person_id')::bigint,(fx->>'source_id')::bigint,fx->>'record_key',v_state->>'state_sha256');
  PERFORM set_config('app.change_set_id','',true);
  SELECT status INTO v_status FROM private.narrative_record_publication WHERE narrative_id=(fx->>'narrative_id')::bigint;
  IF v_status<>'withdrawn' THEN RAISE EXCEPTION 'TASK4_STEP_C: %',v_status; END IF;
  -- I-1: ... og fortrydelig, når bindingen er trukket tilbage.
  SELECT can_reverse,blocking_reason INTO v_can_reverse,v_block
    FROM public.red_person_narrative_publication_history((fx->>'person_id')::bigint)
   WHERE event_type='legacy_migrated';
  IF v_can_reverse IS NOT TRUE OR v_block IS NOT NULL THEN
    RAISE EXCEPTION 'TASK4_HISTORY_WITHDRAWN_BINDING: % %',v_can_reverse,v_block;
  END IF;
  -- (d) legacy_migrated -> ledger tilbage til grandfathered_publication
  v_state:=private.narrative_legacy_state((fx->>'legacy_publication_ref')::uuid,false);
  v_res:=public.red_fortryd_person_narrative_publication_event((r->>'legacy_event_id')::uuid,v_state->>'state_sha256');
  PERFORM set_config('app.change_set_id','',true);
  SELECT status INTO v_status FROM private.narrative_legacy_publication WHERE legacy_publication_ref=(fx->>'legacy_publication_ref')::uuid;
  IF v_status<>'grandfathered_publication' THEN RAISE EXCEPTION 'TASK4_STEP_D: %',v_status; END IF;
  IF v_res->>'status'<>'published' THEN RAISE EXCEPTION 'TASK4_STEP_D_STREAM_STATUS: %',v_res->>'status'; END IF;
  v_state:=private.narrative_legacy_state((fx->>'legacy_publication_ref')::uuid,false);
  IF v_state->>'publication_status'<>'published' OR NOT coalesce((v_state->>'baseline_matches')::boolean,false) THEN
    RAISE EXCEPTION 'TASK4_STEP_D_EDITOR_STATE: % %',v_state->>'publication_status',v_state->>'baseline_matches';
  END IF;
  -- Task 1b: efter fuld fortrydelse er narrativet offentligt igen som legacy —
  -- præcis én gang, og aldrig som source_record (den withdrawn binding må ikke
  -- give en dublet i nogen af de to offentlige funktioner).
  IF NOT public.person_daa_narrative_publication_allowed((fx->>'narrative_id')::bigint) THEN RAISE EXCEPTION 'TASK4_LEGACY_NOT_PUBLIC_AGAIN'; END IF;
  IF (SELECT count(*) FROM public.public_person_bio_source_versions_v2(ARRAY[(fx->>'person_id')::bigint]) WHERE provenance_kind='legacy_narrative')<>1 THEN RAISE EXCEPTION 'TASK4_LEGACY_ROW_MISSING'; END IF;
  IF (SELECT count(*) FROM public.public_person_bio_source_versions_v2(ARRAY[(fx->>'person_id')::bigint]) WHERE provenance_kind='source_record')<>0 THEN RAISE EXCEPTION 'TASK4_WITHDRAWN_BINDING_LEAKED_V2'; END IF;
  IF (SELECT count(*) FROM public.public_person_bio_source_versions_v2(ARRAY[(fx->>'person_id')::bigint]))<>1 THEN RAISE EXCEPTION 'TASK4_DUPLICATE_ROWS_V2'; END IF;
  IF (SELECT count(*) FROM public.public_person_bio_source_versions(ARRAY[(fx->>'person_id')::bigint]) WHERE provenance_kind='legacy_narrative')<>1 THEN RAISE EXCEPTION 'TASK4_LEGACY_ROW_MISSING_V1'; END IF;
  IF (SELECT count(*) FROM public.public_person_bio_source_versions(ARRAY[(fx->>'person_id')::bigint]) WHERE provenance_kind='source_record')<>0 THEN RAISE EXCEPTION 'TASK4_WITHDRAWN_BINDING_LEAKED_V1'; END IF;
  IF (SELECT count(*) FROM public.public_person_bio_source_versions(ARRAY[(fx->>'person_id')::bigint]))<>1 THEN RAISE EXCEPTION 'TASK4_DUPLICATE_ROWS_V1'; END IF;
  -- (e) bound_draft: draft_created ER streamens seneste og kan fortrydes direkte.
  fx:=pg_temp.task3_fixture('T4D',true);
  r:=pg_temp.task3_migrate(fx,'bound_draft','t4d');
  PERFORM set_config('request.jwt.claim.sub',fx->>'actor',true);
  v_state:=private.narrative_record_state((fx->>'person_id')::bigint,(fx->>'source_id')::bigint,fx->>'record_key',false);
  v_res:=public.red_fortryd_person_narrative_publication_event((r->>'draft_event_id')::uuid,v_state->>'state_sha256');
  PERFORM set_config('app.change_set_id','',true);
  IF v_res->>'status'<>'withdrawn' THEN RAISE EXCEPTION 'TASK4_STEP_E: %',v_res->>'status'; END IF;
  -- (f) red_tilbagetraek_legacy_narrative på en migreret række afvises
  fx:=pg_temp.task3_fixture('T4E',false); r:=pg_temp.task3_migrate(fx,'bound_published','t4e');
  PERFORM set_config('request.jwt.claim.sub',fx->>'actor',true);
  v_state:=private.narrative_legacy_state((fx->>'legacy_publication_ref')::uuid,false);
  v_ok:=false;
  BEGIN
    PERFORM public.red_tilbagetraek_legacy_narrative((fx->>'legacy_publication_ref')::uuid,v_state->>'state_sha256','test');
  EXCEPTION WHEN OTHERS THEN v_ok:=SQLERRM LIKE 'NARRATIVE_LEGACY_PUBLICATION_TRANSITION_INVALID%'; v_err:=SQLERRM; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK4_WITHDRAW_MIGRATED_ACCEPTED got %',coalesce(v_err,'(success)'); END IF;
  RAISE NOTICE 'task4 reversal OK';
END $task4_reversal$;

-- Task 9b: registrering af batch-reversal for en ren legacy-migration-batch (spec §8).
-- Hjælper: fortryd ét migreret element fuldt ud og returnér kvitteringen.
CREATE FUNCTION pg_temp.task9b_undo(p_fx jsonb, p_migrate jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $undo$
DECLARE v_state jsonb; v_res jsonb; v_ids jsonb := '[]'::jsonb; v_ledger jsonb := 'null'::jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_fx->>'actor',true);
  IF (p_migrate->'published_event_id') IS DISTINCT FROM 'null'::jsonb THEN
    v_state:=private.narrative_record_state((p_fx->>'person_id')::bigint,(p_fx->>'source_id')::bigint,p_fx->>'record_key',false);
    v_res:=public.red_fortryd_person_narrative_publication_event((p_migrate->>'published_event_id')::uuid,v_state->>'state_sha256');
    PERFORM set_config('app.change_set_id','',true);
    v_ids:=v_ids||to_jsonb(v_res->>'event_id');
    -- Kladden trækkes tilbage med discard (spec §8: draft_created kan ikke fortrydes,
    -- når reversal-eventet allerede er streamens seneste).
    v_state:=private.narrative_record_state((p_fx->>'person_id')::bigint,(p_fx->>'source_id')::bigint,p_fx->>'record_key',false);
    v_res:=public.red_kasser_person_narrative_record((p_fx->>'person_id')::bigint,(p_fx->>'source_id')::bigint,p_fx->>'record_key',v_state->>'state_sha256');
    PERFORM set_config('app.change_set_id','',true);
    -- draft_discarded er også en fortrydelse på bindings-streamen og skal kvitteres.
    v_ids:=v_ids||to_jsonb(v_res->>'event_id');
  ELSE
    v_state:=private.narrative_record_state((p_fx->>'person_id')::bigint,(p_fx->>'source_id')::bigint,p_fx->>'record_key',false);
    v_res:=public.red_fortryd_person_narrative_publication_event((p_migrate->>'draft_event_id')::uuid,v_state->>'state_sha256');
    PERFORM set_config('app.change_set_id','',true);
    v_ids:=v_ids||to_jsonb(v_res->>'event_id');
  END IF;
  IF (p_migrate->'legacy_event_id') IS DISTINCT FROM 'null'::jsonb THEN
    -- Scriptets eneste vej til legacy-streamens state_sha256 for en migreret række.
    v_state:=private.legacy_migration_reversal_state((p_fx->>'legacy_publication_ref')::uuid);
    IF v_state->>'ledger_status'<>'migrated' OR v_state->>'latest_event_type'<>'legacy_migrated' THEN
      RAISE EXCEPTION 'TASK9B_REVERSAL_STATE_UNEXPECTED: %',v_state;
    END IF;
    v_res:=public.red_fortryd_person_narrative_publication_event((p_migrate->>'legacy_event_id')::uuid,v_state->>'state_sha256');
    PERFORM set_config('app.change_set_id','',true);
    v_ids:=v_ids||to_jsonb(v_res->>'event_id');
    v_ledger:=to_jsonb('grandfathered_publication'::text);
  END IF;
  RETURN jsonb_build_object('reversal_event_ids',v_ids,'final_binding_status','withdrawn','final_ledger_status',v_ledger);
END $undo$;

DO $task9b$
DECLARE
  fx_p jsonb; fx_d jsonb; fx_r jsonb; r_p jsonb; r_d jsonb; r_r jsonb;
  rec_p jsonb; rec_d jsonb; rec_r jsonb; res jsonb; v_auth uuid; v_auth2 uuid; v_rows integer; v_status text; v_ok boolean; v_err text;
  k_p text; k_d text; k_r text;
BEGIN
  -- ---- lykkelig vej A: bound_published (to reversals + discard, ledger tilbage) ----
  fx_p:=pg_temp.task3_fixture('T9P',false);
  r_p:=pg_temp.task3_migrate(fx_p,'bound_published','t9p');
  k_p:='legacy-migration:'||(fx_p->>'record_key');
  rec_p:=pg_temp.task9b_undo(fx_p,r_p);
  IF jsonb_array_length(rec_p->'reversal_event_ids')<>3 THEN RAISE EXCEPTION 'TASK9B_EVENT_IDS_P: %',rec_p; END IF;
  PERFORM set_config('request.jwt.claim.sub',fx_p->>'actor',true);
  v_auth:=public.red_authorize_reimport_reversal((r_p->>'batch_id')::uuid,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  res:=private.record_reimport_legacy_reversal((r_p->>'batch_id')::uuid,v_auth,jsonb_build_object(k_p,rec_p));
  IF res->>'batch_status'<>'finalized' OR (res->>'reversed_elements')::int<>1 THEN RAISE EXCEPTION 'TASK9B_RESULT_P: %',res; END IF;
  SELECT status INTO v_status FROM private.reimport_authorization WHERE id=v_auth;
  IF v_status<>'consumed' THEN RAISE EXCEPTION 'TASK9B_AUTH_NOT_CONSUMED: %',v_status; END IF;
  SELECT count(*) INTO v_rows FROM private.reimport_event WHERE batch_id=(r_p->>'batch_id')::uuid AND operation='reversal';
  IF v_rows<>1 THEN RAISE EXCEPTION 'TASK9B_REVERSAL_EVENTS: %',v_rows; END IF;
  SELECT count(*) INTO v_rows FROM private.reimport_event
   WHERE batch_id=(r_p->>'batch_id')::uuid AND element_id='legacy-migration-reversal:'||v_auth::text;
  IF v_rows<>1 THEN RAISE EXCEPTION 'TASK9B_REVERSAL_ELEMENT_ID'; END IF;
  SELECT status INTO v_status FROM private.reimport_batch WHERE id=(r_p->>'batch_id')::uuid;
  IF v_status<>'finalized' THEN RAISE EXCEPTION 'TASK9B_BATCH_STATUS: %',v_status; END IF;

  -- ---- (f) samme batch kan ikke registreres fortrudt to gange ----
  v_auth2:=public.red_authorize_reimport_reversal((r_p->>'batch_id')::uuid,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  v_ok:=false;
  BEGIN
    PERFORM private.record_reimport_legacy_reversal((r_p->>'batch_id')::uuid,v_auth2,jsonb_build_object(k_p,rec_p));
  EXCEPTION WHEN OTHERS THEN v_ok:=SQLERRM LIKE 'REIMPORT_WRITER_REVERSAL_INVALID%'; v_err:=SQLERRM; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK9B_DOUBLE_RECORD_ACCEPTED got %',coalesce(v_err,'(success)'); END IF;
  SELECT count(*) INTO v_rows FROM private.reimport_event WHERE batch_id=(r_p->>'batch_id')::uuid AND operation='reversal';
  IF v_rows<>1 THEN RAISE EXCEPTION 'TASK9B_REVERSAL_EVENTS_AFTER_DOUBLE: %',v_rows; END IF;

  -- ---- lykkelig vej B: bound_draft (én reversal, final_ledger_status = null) ----
  fx_d:=pg_temp.task3_fixture('T9D',true);
  r_d:=pg_temp.task3_migrate(fx_d,'bound_draft','t9d');
  k_d:='legacy-migration:'||(fx_d->>'record_key');
  rec_d:=pg_temp.task9b_undo(fx_d,r_d);
  IF jsonb_array_length(rec_d->'reversal_event_ids')<>1 OR jsonb_typeof(rec_d->'final_ledger_status')<>'null' THEN
    RAISE EXCEPTION 'TASK9B_RECEIPT_D: %',rec_d;
  END IF;
  PERFORM set_config('request.jwt.claim.sub',fx_d->>'actor',true);
  v_auth:=public.red_authorize_reimport_reversal((r_d->>'batch_id')::uuid,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  res:=private.record_reimport_legacy_reversal((r_d->>'batch_id')::uuid,v_auth,jsonb_build_object(k_d,rec_d));
  IF (res->>'reversed_elements')::int<>1 THEN RAISE EXCEPTION 'TASK9B_RESULT_D: %',res; END IF;

  -- ---- afvisninger på en frisk, IKKE fortrudt batch ----
  fx_r:=pg_temp.task3_fixture('T9R',false);
  r_r:=pg_temp.task3_migrate(fx_r,'bound_published','t9r');
  k_r:='legacy-migration:'||(fx_r->>'record_key');
  PERFORM set_config('request.jwt.claim.sub',fx_r->>'actor',true);
  v_auth:=public.red_authorize_reimport_reversal((r_r->>'batch_id')::uuid,gen_random_uuid(),clock_timestamp()+interval '5 minutes');

  -- (a) ukendt batch
  v_ok:=false;
  BEGIN PERFORM private.record_reimport_legacy_reversal(gen_random_uuid(),v_auth,jsonb_build_object(k_r,rec_p));
  EXCEPTION WHEN OTHERS THEN v_ok:=SQLERRM LIKE 'REIMPORT_WRITER_REVERSAL_INVALID%'; v_err:=SQLERRM; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK9B_UNKNOWN_BATCH_ACCEPTED got %',coalesce(v_err,'(success)'); END IF;

  -- (b) autorisation udstedt til en anden batch
  v_ok:=false;
  BEGIN PERFORM private.record_reimport_legacy_reversal((r_d->>'batch_id')::uuid,v_auth,jsonb_build_object(k_d,rec_d));
  EXCEPTION WHEN OTHERS THEN v_ok:=SQLERRM LIKE 'REIMPORT_WRITER_REVERSAL_INVALID%'; v_err:=SQLERRM; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK9B_FOREIGN_AUTH_ACCEPTED got %',coalesce(v_err,'(success)'); END IF;

  -- (c) kvittering med manglende element
  v_ok:=false;
  BEGIN PERFORM private.record_reimport_legacy_reversal((r_r->>'batch_id')::uuid,v_auth,'{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN v_ok:=SQLERRM LIKE 'REIMPORT_LEGACY_REVERSAL_RECEIPT_MISMATCH%'; v_err:=SQLERRM; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK9B_EMPTY_RECEIPT_ACCEPTED got %',coalesce(v_err,'(success)'); END IF;

  -- (d) kvittering hvor bindingen i virkeligheden stadig er published
  v_ok:=false;
  BEGIN PERFORM private.record_reimport_legacy_reversal((r_r->>'batch_id')::uuid,v_auth,
    jsonb_build_object(k_r,jsonb_build_object('reversal_event_ids',rec_p->'reversal_event_ids',
      'final_binding_status','withdrawn','final_ledger_status','grandfathered_publication')));
  EXCEPTION WHEN OTHERS THEN v_ok:=SQLERRM LIKE 'REIMPORT_LEGACY_REVERSAL_RECEIPT_MISMATCH%'; v_err:=SQLERRM; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK9B_PUBLISHED_BINDING_ACCEPTED got %',coalesce(v_err,'(success)'); END IF;

  -- ingen af afvisningerne (a)-(d) må have skrevet noget
  SELECT status INTO v_status FROM private.reimport_authorization WHERE id=v_auth;
  IF v_status<>'issued' THEN RAISE EXCEPTION 'TASK9B_AUTH_CONSUMED_ON_REJECT: %',v_status; END IF;
  SELECT count(*) INTO v_rows FROM private.reimport_event WHERE batch_id=(r_r->>'batch_id')::uuid AND operation='reversal';
  IF v_rows<>0 THEN RAISE EXCEPTION 'TASK9B_REJECTED_WROTE_EVENT: %',v_rows; END IF;

  -- (e1) kvittering der citerer et fremmed narrativs fortrydelses-event
  --      (T9R er fuldt migreret, men ikke fortrudt — vi fortryder den nu, så kun
  --       event-id-mængden kan afvige)
  rec_r:=pg_temp.task9b_undo(fx_r,r_r);
  PERFORM set_config('request.jwt.claim.sub',fx_r->>'actor',true);
  v_ok:=false;
  BEGIN PERFORM private.record_reimport_legacy_reversal((r_r->>'batch_id')::uuid,v_auth,
    jsonb_build_object(k_r,jsonb_set(rec_r,'{reversal_event_ids}',
      (rec_r->'reversal_event_ids')||(rec_p->'reversal_event_ids'->0))));
  EXCEPTION WHEN OTHERS THEN v_ok:=SQLERRM LIKE 'REIMPORT_LEGACY_REVERSAL_RECEIPT_MISMATCH%'; v_err:=SQLERRM; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK9B_FOREIGN_EVENT_ID_ACCEPTED got %',coalesce(v_err,'(success)'); END IF;

  -- (e2) kvittering med ét manglende id
  v_ok:=false;
  BEGIN PERFORM private.record_reimport_legacy_reversal((r_r->>'batch_id')::uuid,v_auth,
    jsonb_build_object(k_r,jsonb_set(rec_r,'{reversal_event_ids}',
      jsonb_build_array(rec_r->'reversal_event_ids'->0))));
  EXCEPTION WHEN OTHERS THEN v_ok:=SQLERRM LIKE 'REIMPORT_LEGACY_REVERSAL_RECEIPT_MISMATCH%'; v_err:=SQLERRM; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK9B_MISSING_EVENT_ID_ACCEPTED got %',coalesce(v_err,'(success)'); END IF;

  -- (e3) den korrekte, fuldt sporede kvittering accepteres (positiv kontrol)
  res:=private.record_reimport_legacy_reversal((r_r->>'batch_id')::uuid,v_auth,jsonb_build_object(k_r,rec_r));
  IF (res->>'reversed_elements')::int<>1 THEN RAISE EXCEPTION 'TASK9B_RESULT_R: %',res; END IF;

  -- (f) uden redaktion-aktør
  PERFORM set_config('request.jwt.claim.sub','',true);
  v_ok:=false;
  BEGIN PERFORM private.record_reimport_legacy_reversal((r_r->>'batch_id')::uuid,v_auth,jsonb_build_object(k_r,rec_p));
  EXCEPTION WHEN OTHERS THEN v_ok:=SQLERRM LIKE 'REIMPORT_WRITER_ROLE_FORBIDDEN%'; v_err:=SQLERRM; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK9B_NO_ACTOR_ACCEPTED got %',coalesce(v_err,'(success)'); END IF;
  v_ok:=false;
  BEGIN PERFORM private.legacy_migration_reversal_state((fx_r->>'legacy_publication_ref')::uuid);
  EXCEPTION WHEN OTHERS THEN v_ok:=SQLERRM LIKE 'REIMPORT_WRITER_ROLE_FORBIDDEN%'; v_err:=SQLERRM; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK9B_STATE_NO_ACTOR_ACCEPTED got %',coalesce(v_err,'(success)'); END IF;
  PERFORM set_config('request.jwt.claim.sub',fx_r->>'actor',true);

  -- efter den accepterede (e3) er autorisationen forbrugt og der er præcis én reversal-hændelse
  SELECT status INTO v_status FROM private.reimport_authorization WHERE id=v_auth;
  IF v_status<>'consumed' THEN RAISE EXCEPTION 'TASK9B_AUTH_NOT_CONSUMED_R: %',v_status; END IF;
  SELECT count(*) INTO v_rows FROM private.reimport_event WHERE batch_id=(r_r->>'batch_id')::uuid AND operation='reversal';
  IF v_rows<>1 THEN RAISE EXCEPTION 'TASK9B_REVERSAL_EVENTS_R: %',v_rows; END IF;
  RAISE NOTICE 'task9b batch reversal OK';
END $task9b$;

ROLLBACK;
