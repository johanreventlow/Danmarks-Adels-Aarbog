-- Omsegmentering (spec 2026-09-27, Task 1): klausulsæt, sæt-hash, aktuelt sæt og
-- invarianterne i de selvstændige triggere. Alt syntetisk; én transaktion, rulles tilbage.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.expect_error(p_sql text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM IS NULL OR SQLERRM NOT LIKE p_token||'%' THEN
      RAISE EXCEPTION 'CLAUSE_SET_TEST_WRONG_ERROR: expected % got %', p_token, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'CLAUSE_SET_TEST_NO_ERROR: expected %', p_token;
END $$;

-- Helpost med tre sætninger: [0,30) [31,55) [56,65).
CREATE FUNCTION pg_temp.fixture() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_source bigint := -148901; v_run uuid := gen_random_uuid(); v_rend uuid; v_occ uuid; v_parent uuid;
  v_text text := 'Alfa Bravo, f. 1801 i Charlie. Gift 1830 m. Delta Echo. Død 1860.';
BEGIN
  INSERT INTO public.source(id,slags,titel,udgave,aar) VALUES(v_source,'DAA-udgave','Clause set fixture','synthetic',1900) ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES(v_run,v_source,'clause-set-'||v_run::text,'fixture','fixture','fixture',repeat('1',64),'{}');
  INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata)
  VALUES(v_source,'clause-set-r-'||v_run::text,'pdf_text_layer',repeat('2',64),'{}') RETURNING id INTO v_rend;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  VALUES(v_rend,'occ-set-1',10,10,100,100+char_length(v_text),v_text,repeat('3',64),repeat('4',64),v_run) RETURNING id INTO v_occ;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id)
  VALUES(v_occ,'person_post',10,10,100,100+char_length(v_text),v_text,'clear','fixture',v_run) RETURNING id INTO v_parent;
  RETURN jsonb_build_object('source',v_source,'run',v_run,'occ',v_occ,'parent',v_parent,'text',v_text);
END $$;

CREATE FUNCTION pg_temp.new_run(fx jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_run uuid := gen_random_uuid();
BEGIN
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES(v_run,(fx->>'source')::bigint,'clause-set-'||v_run::text,'fixture','fixture','fixture',repeat('5',64),'{}');
  RETURN v_run;
END $$;

-- SQL-tekst for én klausul; post-relativ [a,b), sæt, ordinal, flag, kørsel.
CREATE FUNCTION pg_temp.clause_sql(fx jsonb, p_seq integer, p_ordinal integer, p_a integer, p_b integer,
                                   p_flags jsonb DEFAULT '[]', p_run uuid DEFAULT NULL) RETURNS text LANGUAGE sql AS $$
  SELECT format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,
         parent_observation_id,post_char_from,post_char_to,clause_ordinal,clause_classification,clause_flags,clause_set_seq)
       VALUES(%L,'clause',10,10,%s,%s,%L,'clear','clause_segment_v1',%L,%L,%s,%s,%s,'record_text',%L,%s)$q$,
    fx->>'occ', 100+p_a, 100+p_b, substr(fx->>'text', p_a+1, p_b-p_a), coalesce(p_run,(fx->>'run')::uuid), fx->>'parent',
    p_a, p_b, p_ordinal, p_flags::text, coalesce(p_seq::text,'NULL'))
$$;

CREATE FUNCTION pg_temp.clause(fx jsonb, p_seq integer, p_ordinal integer, p_a integer, p_b integer,
                               p_flags jsonb DEFAULT '[]', p_run uuid DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  EXECUTE pg_temp.clause_sql(fx,p_seq,p_ordinal,p_a,p_b,p_flags,p_run)||' RETURNING id' INTO v_id;
  RETURN v_id;
END $$;

DO $t1_catalog$
DECLARE v_def text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='private' AND table_name='source_observation'
                  AND column_name='clause_set_seq' AND is_nullable='YES' AND column_default IS NULL) THEN
    RAISE EXCEPTION 'CLAUSE_SET_COLUMN_INVALID: clause_set_seq skal være nullable uden default';
  END IF;
  SELECT indexdef INTO v_def FROM pg_indexes WHERE schemaname='private' AND indexname='ux_source_observation_clause_ordinal';
  IF v_def IS NULL OR v_def NOT LIKE '%COALESCE(clause_set_seq, 1)%' THEN
    RAISE EXCEPTION 'CLAUSE_SET_INDEX_INVALID: %', v_def;
  END IF;
  IF (SELECT count(*) FROM pg_indexes WHERE schemaname='private' AND tablename='source_observation' AND indexdef LIKE '%clause_ordinal%')<>1 THEN
    RAISE EXCEPTION 'CLAUSE_SET_INDEX_DUPLICATE';
  END IF;
  IF to_regclass('private.clause_observation_current') IS NULL THEN RAISE EXCEPTION 'CLAUSE_SET_VIEW_MISSING'; END IF;
  IF to_regprocedure('private.clause_set_sha256(uuid,integer)') IS NULL THEN RAISE EXCEPTION 'CLAUSE_SET_HASH_MISSING'; END IF;
  IF NOT EXISTS (SELECT 1 FROM private.vocab WHERE scheme='clause_disposition_machine' AND code='erstattet') THEN
    RAISE EXCEPTION 'CLAUSE_SET_VOCAB_MISSING';
  END IF;
  IF pg_get_constraintdef((SELECT oid FROM pg_constraint WHERE conname='reimport_event_operation_check')) NOT LIKE '%clause_revision%' THEN
    RAISE EXCEPTION 'CLAUSE_SET_OPERATION_MISSING';
  END IF;
  -- Writeren skriver via den fælles sæt-funktion, som sætter clause_set_seq.
  IF pg_get_functiondef('private.write_clause_evidence(uuid,text,jsonb)'::regprocedure) NOT LIKE '%private.clause_write_set(%'
     OR pg_get_functiondef('private.clause_write_set(jsonb,jsonb,integer,text)'::regprocedure) NOT LIKE '%clause_set_seq%' THEN
    RAISE EXCEPTION 'CLAUSE_SET_WRITER_NOT_UPGRADED';
  END IF;
  -- De tre triggere findes og er aktive.
  IF (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal AND tgenabled<>'D' AND tgname IN
       ('trg_source_observation_clause_set','trg_clause_set_density','trg_clause_disposition_set_rule',
        'trg_interpretation_observation_current_clause'))<>4 THEN
    RAISE EXCEPTION 'CLAUSE_SET_TRIGGERS_MISSING';
  END IF;
  -- Triggerrækkefølgen er bærende: PostgreSQL fyrer BEFORE-triggere alfabetisk. Klausul-
  -- valideringen skal komme før sæt-reglen (ellers skygger SET_REQUIRED de eksisterende
  -- fejlkoder), og sæt-reglen for dispositioner før den generelle validering.
  IF NOT ('trg_source_observation_clause' < 'trg_source_observation_clause_set' COLLATE "C"
          AND 'trg_clause_disposition_set_rule' < 'trg_clause_disposition_validate' COLLATE "C"
          AND 'trg_interpretation_observation_current_clause' < 'trg_interpretation_observation_scope' COLLATE "C") THEN
    RAISE EXCEPTION 'CLAUSE_SET_TRIGGER_ORDER';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_source_observation_clause' AND tgrelid='private.source_observation'::regclass)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_clause_disposition_validate' AND tgrelid='private.clause_disposition'::regclass)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_interpretation_observation_scope' AND tgrelid='private.interpretation_observation'::regclass) THEN
    RAISE EXCEPTION 'CLAUSE_SET_TRIGGER_ORDER_BASELINE_RENAMED';
  END IF;
  -- Sæt-reglen fyrer før validate_clause_disposition og må derfor selv tage rækkelåsen
  -- (review R1 fund 1): ellers læses "aktuelt sæt" før en samtidig revision er synlig.
  IF pg_get_functiondef('private.validate_clause_disposition_set()'::regprocedure)
       !~ 'FROM private\.source_observation WHERE id=NEW\.observation_id FOR UPDATE' THEN
    RAISE EXCEPTION 'CLAUSE_SET_DISPOSITION_RULE_UNLOCKED';
  END IF;
  -- Klausul-writeren håndhæver tætheden ved slutningen som revisionen (spec §3.1).
  IF pg_get_functiondef('private.write_clause_evidence(uuid,text,jsonb)'::regprocedure)
       NOT LIKE '%SET CONSTRAINTS private.trg_clause_set_density IMMEDIATE%' THEN
    RAISE EXCEPTION 'CLAUSE_SET_WRITER_DENSITY_DEFERRED';
  END IF;
  RAISE NOTICE 't1 catalog OK';
END $t1_catalog$;

DO $t2_seq_rules$
DECLARE fx jsonb; v_run2 uuid;
BEGIN
  fx := pg_temp.fixture();
  -- Ikke-klausul med sæt ⇒ afvist.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,clause_set_seq)
       VALUES(%L,'person',10,10,100,101,'A','clear','x',%L,1)$q$, fx->>'occ', fx->>'run'),
    'EVIDENCE_CLAUSE_SET_FORBIDDEN');
  -- Klausul uden sæt — sådan skriver en gammel writerkrop — ⇒ afvist.
  PERFORM pg_temp.expect_error(pg_temp.clause_sql(fx,NULL,1,0,30), 'EVIDENCE_CLAUSE_SET_REQUIRED');
  -- Ny post: første sæt skal være 1.
  PERFORM pg_temp.expect_error(pg_temp.clause_sql(fx,2,1,0,30), 'EVIDENCE_CLAUSE_SET_SEQ_INVALID');
  PERFORM pg_temp.clause(fx,1,1,0,30);
  PERFORM pg_temp.clause(fx,1,2,31,55);
  -- Sæt 1 er én kørsel: en anden kørsel kan ikke lægge en klausul i det.
  v_run2 := pg_temp.new_run(fx);
  PERFORM pg_temp.expect_error(pg_temp.clause_sql(fx,1,3,56,65,'[]',v_run2), 'EVIDENCE_CLAUSE_SET_SEQ_INVALID');
  -- Hul i sæt-rækken ⇒ afvist; max+1 med ny kørsel ⇒ tilladt, og resten af sættet i samme kørsel.
  PERFORM pg_temp.expect_error(pg_temp.clause_sql(fx,3,1,0,65,'[]',v_run2), 'EVIDENCE_CLAUSE_SET_SEQ_INVALID');
  PERFORM pg_temp.clause(fx,2,1,0,55,'[]',v_run2);
  PERFORM pg_temp.clause(fx,2,2,56,65,'[]',v_run2);
  -- Det afløste sæt kan ikke få flere rækker (heller ikke fra sin egen kørsel).
  PERFORM pg_temp.expect_error(pg_temp.clause_sql(fx,1,3,56,65), 'EVIDENCE_CLAUSE_SET_SEQ_INVALID');
  -- Samme ordinal i samme sæt ⇒ unikhedsindekset.
  PERFORM pg_temp.expect_error(pg_temp.clause_sql(fx,2,2,56,65,'[]',v_run2), 'duplicate key value');
  SET CONSTRAINTS ALL IMMEDIATE;
  SET CONSTRAINTS ALL DEFERRED;
  RAISE NOTICE 't2 seq rules OK';
END $t2_seq_rules$;

DO $t3_density$
DECLARE fx jsonb;
BEGIN
  fx := pg_temp.fixture();
  -- Hele tilfældet i en undertransaktion, så de udskudte hændelser rulles tilbage med den.
  BEGIN
    PERFORM pg_temp.clause(fx,1,1,0,30);
    PERFORM pg_temp.clause(fx,1,3,56,65);   -- hul: ordinal 2 mangler
    SET CONSTRAINTS private.trg_clause_set_density IMMEDIATE;
    RAISE EXCEPTION 'CLAUSE_SET_TEST_NO_ERROR: tæthed';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM IS NULL OR SQLERRM NOT LIKE 'EVIDENCE_CLAUSE_SET_NOT_DENSE%' THEN
      RAISE EXCEPTION 'CLAUSE_SET_TEST_WRONG_ERROR: expected EVIDENCE_CLAUSE_SET_NOT_DENSE got %', SQLERRM;
    END IF;
  END;
  SET CONSTRAINTS ALL DEFERRED;
  RAISE NOTICE 't3 density OK';
END $t3_density$;

DO $t4_legacy_null_is_set_1$
DECLARE fx jsonb; v_run2 uuid; v_n integer;
BEGIN
  fx := pg_temp.fixture();
  -- 4.1c's rækker har NULL. Simulér dem med triggerne slået fra via replica-rollen
  -- (kræver superbruger som i CI; rulles tilbage med filen).
  PERFORM set_config('session_replication_role','replica',true);
  PERFORM pg_temp.clause(fx,NULL,1,0,30);
  PERFORM pg_temp.clause(fx,NULL,2,31,55);
  PERFORM set_config('session_replication_role','origin',true);
  -- NULL tæller som sæt 1 i unikhed og i sæt-rækken.
  v_run2 := pg_temp.new_run(fx);
  PERFORM pg_temp.expect_error(pg_temp.clause_sql(fx,1,1,0,30,'[]',v_run2), 'EVIDENCE_CLAUSE_SET_SEQ_INVALID');
  PERFORM pg_temp.clause(fx,2,1,0,55,'[]',v_run2);
  SELECT count(*) INTO v_n FROM private.clause_observation_current WHERE parent_observation_id=(fx->>'parent')::uuid;
  IF v_n<>1 THEN RAISE EXCEPTION 'CLAUSE_SET_VIEW_NOT_CURRENT: %', v_n; END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  SET CONSTRAINTS ALL DEFERRED;
  RAISE NOTICE 't4 legacy NULL = set 1 OK';
END $t4_legacy_null_is_set_1$;

DO $t5_set_hash$
DECLARE fx jsonb; v_run2 uuid; h1 text; h2 text; h3 text;
BEGIN
  fx := pg_temp.fixture();
  PERFORM pg_temp.clause(fx,1,1,0,30,'["short_clause","unknown_abbreviation"]');
  h1 := private.clause_set_sha256((fx->>'parent')::uuid,1);
  -- Paritetslås: samme hash som tests/fixtures/clause-set-sha256.json (Python-siden, Task 5).
  IF h1 IS DISTINCT FROM '671585aa3b736ebb9d3f5f2e9146fcefd2c4a1314743b011d14c29aae72acbc8' THEN
    RAISE EXCEPTION 'CLAUSE_SET_HASH_PARITY: %', h1;
  END IF;
  -- Samme spans, flag i anden rækkefølge og med dublet ⇒ samme hash.
  v_run2 := pg_temp.new_run(fx);
  PERFORM pg_temp.clause(fx,2,1,0,30,'["unknown_abbreviation","short_clause","short_clause"]',v_run2);
  h2 := private.clause_set_sha256((fx->>'parent')::uuid,2);
  IF h2 IS DISTINCT FROM h1 THEN RAISE EXCEPTION 'CLAUSE_SET_HASH_FLAG_ORDER: % %', h1, h2; END IF;
  -- Kun flag ændret ⇒ anden hash (en flag-ændring er ikke en no-op).
  PERFORM pg_temp.clause(fx,3,1,0,30,'["short_clause"]',pg_temp.new_run(fx));
  h3 := private.clause_set_sha256((fx->>'parent')::uuid,3);
  IF h3 = h1 THEN RAISE EXCEPTION 'CLAUSE_SET_HASH_IGNORES_FLAGS'; END IF;
  -- NULL-sættet og sæt 1 er det samme sæt.
  IF private.clause_set_sha256((fx->>'parent')::uuid,99) IS NOT NULL THEN RAISE EXCEPTION 'CLAUSE_SET_HASH_EMPTY_NOT_NULL'; END IF;
  RAISE NOTICE 't5 set hash OK (%)', h1;
END $t5_set_hash$;

DO $t6_disposition_rule$
DECLARE fx jsonb; v_old uuid; v_new uuid; v_run2 uuid; v_ev jsonb;
BEGIN
  fx := pg_temp.fixture();
  v_ev := jsonb_build_object('extraction_run_id',fx->>'run','manifest_sha256',repeat('d',64));
  v_old := pg_temp.clause(fx,1,1,0,30);
  INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence) VALUES(v_old,1,'afventer_fortolkning','machine',v_ev);
  -- erstattet i det aktuelle sæt ⇒ afvist.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence) VALUES(%L,2,'erstattet','machine',%L)$q$, v_old, v_ev),
    'EVIDENCE_CLAUSE_DISPOSITION_REPLACED_IN_CURRENT_SET');
  v_run2 := pg_temp.new_run(fx);
  v_new := pg_temp.clause(fx,2,1,0,30,'["short_clause"]',v_run2);
  -- Ny disposition på det afløste sæt (andet end erstattet) ⇒ afvist.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence) VALUES(%L,2,'fortolkning_foreslaaet','machine',%L)$q$, v_old, v_ev),
    'EVIDENCE_CLAUSE_DISPOSITION_OUTSIDE_CURRENT_SET');
  INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence) VALUES(v_old,2,'erstattet','machine',v_ev);
  -- Intet efter erstattet — heller ikke erstattet igen.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence) VALUES(%L,3,'erstattet','machine',%L)$q$, v_old, v_ev),
    'EVIDENCE_CLAUSE_DISPOSITION_AFTER_REPLACED');
  -- Det aktuelle sæt tager almindelige dispositioner.
  INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence) VALUES(v_new,1,'maskinelt_flagget','machine',v_ev);
  RAISE NOTICE 't6 disposition rule OK';
END $t6_disposition_rule$;

DO $t7_interpretation_link$
DECLARE fx jsonb; v_old uuid; v_new uuid;
BEGIN
  fx := pg_temp.fixture();
  v_old := pg_temp.clause(fx,1,1,0,30);
  v_new := pg_temp.clause(fx,2,1,0,30,'[]',pg_temp.new_run(fx));
  -- Link til en klausul i et afløst sæt ⇒ afvist af den selvstændige trigger (før FK og øvrige tjek).
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal) VALUES(gen_random_uuid(),%L,'supporting',1)$q$, v_old),
    'INTERPRETATION_OBSERVATION_CLAUSE_NOT_CURRENT');
  -- Link til det aktuelle sæt passerer denne trigger (og fejler først på noget andet).
  BEGIN
    EXECUTE format($q$INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal) VALUES(gen_random_uuid(),%L,'supporting',1)$q$, v_new);
    SET CONSTRAINTS ALL IMMEDIATE;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'INTERPRETATION_OBSERVATION_CLAUSE_NOT_CURRENT%' THEN
      RAISE EXCEPTION 'CLAUSE_SET_TEST_WRONG_ERROR: aktuelt sæt blev afvist';
    END IF;
  END;
  SET CONSTRAINTS ALL DEFERRED;
  RAISE NOTICE 't7 interpretation link OK';
END $t7_interpretation_link$;

ROLLBACK;
