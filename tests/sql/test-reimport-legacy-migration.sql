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

ROLLBACK;
