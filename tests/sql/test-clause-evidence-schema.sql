-- #148 4.1a: klausul-skema — kolonner, vokabular, triggere og dispositionsledger.
-- Alt syntetisk. Filen kører i én transaktion og ruller altid tilbage.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.expect_error(p_sql text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE p_token||'%' THEN
      RAISE EXCEPTION 'CLAUSE_SCHEMA_TEST_WRONG_ERROR: expected % got %', p_token, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'CLAUSE_SCHEMA_TEST_NO_ERROR: expected %', p_token;
END $$;

-- Fixture: source, run, rendition, occurrence og helpost (kind person_post).
CREATE FUNCTION pg_temp.fixture() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_source bigint := -148001; v_run uuid := gen_random_uuid(); v_rend uuid; v_occ uuid; v_parent uuid;
  v_text text := 'Alfa Bravo, f. 1801 i Charlie. Gift 1830 m. Delta Echo. Død 1860.';
BEGIN
  INSERT INTO public.source(id,slags,titel,udgave,aar) VALUES(v_source,'DAA-udgave','Clause fixture','synthetic',1900) ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES(v_run,v_source,'clause-schema-'||v_run::text,'fixture','fixture','fixture',repeat('1',64),'{}');
  INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata)
  VALUES(v_source,'clause-r-'||v_run::text,'pdf_text_layer',repeat('2',64),'{}') RETURNING id INTO v_rend;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  VALUES(v_rend,'occ-1',10,10,100,100+char_length(v_text),v_text,repeat('3',64),repeat('4',64),v_run) RETURNING id INTO v_occ;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id)
  VALUES(v_occ,'person_post',10,10,100,100+char_length(v_text),v_text,'clear','fixture',v_run) RETURNING id INTO v_parent;
  RETURN jsonb_build_object('run',v_run,'occ',v_occ,'parent',v_parent,'text',v_text);
END $$;

DO $t1_columns_and_vocab$
DECLARE fx jsonb; v_kind text;
BEGIN
  FOREACH v_kind IN ARRAY ARRAY['parent_observation_id','clause_ordinal','clause_classification','clause_flags'] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='private' AND table_name='source_observation' AND column_name=v_kind) THEN
      RAISE EXCEPTION 'CLAUSE_SCHEMA_COLUMN_MISSING: %', v_kind;
    END IF;
  END LOOP;
  IF to_regclass('private.vocab') IS NULL THEN RAISE EXCEPTION 'CLAUSE_SCHEMA_PRIVATE_VOCAB_MISSING'; END IF;
  FOREACH v_kind IN ARRAY ARRAY['person_post','person','fact','marriage','relationship','structural_context','cross_reference','clause',
    'header','name_clause','death_clause','person_name','name'] LOOP
    IF NOT EXISTS (SELECT 1 FROM private.vocab WHERE scheme='observation_kind' AND code=v_kind) THEN
      RAISE EXCEPTION 'CLAUSE_SCHEMA_OBSERVATION_KIND_NOT_SEEDED: %', v_kind;
    END IF;
  END LOOP;
  fx := pg_temp.fixture();
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id)
       VALUES(%L,'ukendt_slags',10,10,100,101,'A','clear','fixture',%L)$q$, fx->>'occ', fx->>'run'),
    'EVIDENCE_OBSERVATION_KIND_UNKNOWN');
  RAISE NOTICE 't1 columns and vocab OK';
END $t1_columns_and_vocab$;

DO $t2_clause_trigger$
DECLARE fx jsonb; v_clause uuid; v_text text; v_len integer;
BEGIN
  fx := pg_temp.fixture(); v_text := fx->>'text'; v_len := char_length(v_text);
  -- Gyldig klausul: første sætning, helpost-relativ [0,30) → absolut [100,130).
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,
    parent_observation_id,clause_ordinal,clause_classification,clause_flags)
  VALUES((fx->>'occ')::uuid,'clause',10,10,100,130,substr(v_text,1,30),'clear','clause_segment_v1',(fx->>'run')::uuid,
    (fx->>'parent')::uuid,1,'record_text','[]'::jsonb) RETURNING id INTO v_clause;
  -- Klausul uden forælder.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',10,10,130,140,%L,'clear','clause_segment_v1',%L,2,'record_text','[]')$q$, fx->>'occ', substr(v_text,31,10), fx->>'run'),
    'EVIDENCE_CLAUSE_PARENT_REQUIRED');
  -- Ikke-klausul med forælder.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id)
       VALUES(%L,'person_post',10,10,100,101,'A','clear','x',%L,%L)$q$, fx->>'occ', fx->>'run', fx->>'parent'),
    'EVIDENCE_CLAUSE_PARENT_FORBIDDEN');
  -- Forælder er selv en klausul.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',10,10,100,105,%L,'clear','clause_segment_v1',%L,%L,1,'record_text','[]')$q$, fx->>'occ', substr(v_text,1,5), fx->>'run', v_clause),
    'EVIDENCE_CLAUSE_PARENT_NOT_TOP_LEVEL');
  -- Span uden for forælderen.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',10,10,%s,%s,'x','clear','clause_segment_v1',%L,%L,2,'record_text','[]')$q$, fx->>'occ', 100+v_len, 100+v_len+1, fx->>'run', fx->>'parent'),
    'EVIDENCE_CLAUSE_SPAN_OUTSIDE_PARENT');
  -- Sideinterval uden for forælderen (spec 4.1.2: klausulen arver forælderens grænser).
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',9,10,130,140,%L,'clear','clause_segment_v1',%L,%L,2,'record_text','[]')$q$, fx->>'occ', substr(v_text,31,10), fx->>'run', fx->>'parent'),
    'EVIDENCE_CLAUSE_PAGE_OUTSIDE_PARENT');
  -- Tekst ≠ udsnit af forælderen.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',10,10,130,140,'FORKERT TEKST','clear','clause_segment_v1',%L,%L,2,'record_text','[]')$q$, fx->>'occ', fx->>'run', fx->>'parent'),
    'EVIDENCE_CLAUSE_TEXT_MISMATCH');
  -- Ukendt klassifikation.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',10,10,130,140,%L,'clear','clause_segment_v1',%L,%L,2,'layout','[]')$q$, fx->>'occ', substr(v_text,31,10), fx->>'run', fx->>'parent'),
    'EVIDENCE_CLAUSE_CLASSIFICATION_UNKNOWN');
  -- Dublet-ordinal under samme forælder.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',10,10,130,140,%L,'clear','clause_segment_v1',%L,%L,1,'record_text','[]')$q$, fx->>'occ', substr(v_text,31,10), fx->>'run', fx->>'parent'),
    'duplicate key value');
  RAISE NOTICE 't2 clause trigger OK';
END $t2_clause_trigger$;

DO $t3_disposition_ledger$
DECLARE fx jsonb; v_clause uuid; v_actor uuid; v_current text;
BEGIN
  fx := pg_temp.fixture();
  SELECT id INTO v_actor FROM public.profiles WHERE rolle='redaktion' ORDER BY id LIMIT 1;
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'CLAUSE_TEST_ACTOR_MISSING: kør tests/sql/reimport-writer-v2-bootstrap.sql først';
  END IF;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
  VALUES((fx->>'occ')::uuid,'clause',10,10,100,130,substr(fx->>'text',1,30),'clear','clause_segment_v1',(fx->>'run')::uuid,(fx->>'parent')::uuid,1,'record_text','["unknown_abbreviation"]'::jsonb) RETURNING id INTO v_clause;
  -- Maskinel version 1 med gyldig proveniens.
  INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence)
  VALUES(v_clause,1,'maskinelt_flagget','machine',
    jsonb_build_object('extraction_run_id',fx->>'run','manifest_sha256',repeat('d',64)));
  -- Maskinel disposition uden run-/manifest-hash afvises (spec 4.1.2).
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence) VALUES(%L,2,'afventer_fortolkning','machine','{"manifest_sha256":"fixture"}')$q$, v_clause),
    'EVIDENCE_CLAUSE_DISPOSITION_PROVENANCE_INVALID');
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence) VALUES(%L,2,'afventer_fortolkning','machine',jsonb_build_object('extraction_run_id',%L))$q$, v_clause, fx->>'run'),
    'EVIDENCE_CLAUSE_DISPOSITION_PROVENANCE_INVALID');
  -- Version skal være fortløbende.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence) VALUES(%L,3,'afventer_fortolkning','machine','{"x":1}')$q$, v_clause),
    'EVIDENCE_CLAUSE_DISPOSITION_VERSION_INVALID');
  -- Maskine må ikke skrive en endelig (menneskelig) disposition.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence) VALUES(%L,2,'struktureret','machine','{"x":1}')$q$, v_clause),
    'EVIDENCE_CLAUSE_DISPOSITION_KIND_MISMATCH');
  -- Ukendt disposition.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence) VALUES(%L,2,'noget_andet','machine','{"x":1}')$q$, v_clause),
    'EVIDENCE_CLAUSE_DISPOSITION_UNKNOWN');
  -- Menneske uden aktørfelter → CHECK.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence) VALUES(%L,2,'struktureret','human','{"basis":"test"}')$q$, v_clause),
    'new row for relation "clause_disposition" violates check constraint');
  -- Disposition på en ikke-klausul afvises.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence) VALUES(%L,1,'afventer_fortolkning','machine','{"x":1}')$q$, fx->>'parent'),
    'EVIDENCE_CLAUSE_DISPOSITION_TARGET_INVALID');
  -- Menneskelig version 2 og view.
  INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,decided_by,decided_by_name,decided_at,evidence)
  VALUES(v_clause,2,'struktureret','human',v_actor,'Fixture redaktør',clock_timestamp(),'{"basis":"test"}');
  SELECT disposition INTO v_current FROM private.clause_disposition_current WHERE observation_id=v_clause;
  IF v_current<>'struktureret' THEN RAISE EXCEPTION 'CLAUSE_SCHEMA_CURRENT_VIEW_WRONG: %', v_current; END IF;
  RAISE NOTICE 't3 disposition ledger OK';
END $t3_disposition_ledger$;

-- #148 4.1a (Codex-review): en flersidet helpost må ikke få klausuler med et
-- snævrere sideinterval — det ville påstå en finere sidelokalisering end
-- segmenteringen kan vide (spec 4.1.2). Klausulen arver intervallet uændret.
DO $t4_multipage_parent$
DECLARE v_source bigint := -148002; v_run uuid := gen_random_uuid(); v_rend uuid; v_occ uuid; v_parent uuid;
  v_text text := 'Foxtrot Golf, f. 1750. Til Hotel. Død 1799.';
BEGIN
  INSERT INTO public.source(id,slags,titel,udgave,aar) VALUES(v_source,'DAA-udgave','Clause fixture 2','synthetic',1900) ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES(v_run,v_source,'clause-mp-'||v_run::text,'fixture','fixture','fixture',repeat('5',64),'{}');
  INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata)
  VALUES(v_source,'clause-mp-r-'||v_run::text,'pdf_text_layer',repeat('6',64),'{}') RETURNING id INTO v_rend;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  VALUES(v_rend,'occ-mp',20,21,0,char_length(v_text),v_text,repeat('7',64),repeat('8',64),v_run) RETURNING id INTO v_occ;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id)
  VALUES(v_occ,'person_post',20,21,0,char_length(v_text),v_text,'clear','fixture',v_run) RETURNING id INTO v_parent;

  -- Negativ: klausul kun på side 20 under en forælder på 20-21.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',20,20,0,13,%L,'clear','clause_segment_v1',%L,%L,1,'record_text','[]')$q$,
    v_occ, substr(v_text,1,13), v_run, v_parent),
    'EVIDENCE_CLAUSE_PAGE_OUTSIDE_PARENT');

  -- Positiv: samme sideinterval som forælderen accepteres.
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,
    parent_observation_id,clause_ordinal,clause_classification,clause_flags)
  VALUES(v_occ,'clause',20,21,0,13,substr(v_text,1,13),'clear','clause_segment_v1',v_run,v_parent,1,'record_text','[]');

  RAISE NOTICE 't4 multipage parent OK';
END $t4_multipage_parent$;

-- #148 4.1a (Codex-review): klausulens provenance. Spec 4.1.2 siger, at klausulen
-- arver forælderens quality_status og bæres af den versionerede segmenteringsregel.
-- Uden disse tre kontroller kunne en klausul påstå 'clear' under en usikker helpost,
-- bære en vilkårlig extraction_method og gemme uforståelige flag.
DO $t5_clause_provenance$
DECLARE v_source bigint := -148003; v_run uuid := gen_random_uuid(); v_rend uuid; v_occ uuid; v_parent uuid;
  v_text text := 'India Juliett, f. 1690. Til Kilo. Død 1745.';
BEGIN
  INSERT INTO public.source(id,slags,titel,udgave,aar) VALUES(v_source,'DAA-udgave','Clause fixture 3','synthetic',1900) ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES(v_run,v_source,'clause-pv-'||v_run::text,'fixture','fixture','fixture',repeat('9',64),'{}');
  INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata)
  VALUES(v_source,'clause-pv-r-'||v_run::text,'pdf_text_layer',repeat('a',64),'{}') RETURNING id INTO v_rend;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  VALUES(v_rend,'occ-pv',30,30,0,char_length(v_text),v_text,repeat('b',64),repeat('c',64),v_run) RETURNING id INTO v_occ;
  -- Helposten er OCR-usikker.
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id)
  VALUES(v_occ,'person_post',30,30,0,char_length(v_text),v_text,'ocr_uncertain','fixture',v_run) RETURNING id INTO v_parent;

  -- En klausul må ikke opgradere kvaliteten til 'clear'.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',30,30,0,14,%L,'clear','clause_segment_v1',%L,%L,1,'record_text','[]')$q$,
    v_occ, substr(v_text,1,14), v_run, v_parent),
    'EVIDENCE_CLAUSE_QUALITY_MISMATCH');

  -- Vilkårlig extraction_method afvises.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',30,30,0,14,%L,'ocr_uncertain','x',%L,%L,1,'record_text','[]')$q$,
    v_occ, substr(v_text,1,14), v_run, v_parent),
    'EVIDENCE_CLAUSE_EXTRACTION_METHOD_INVALID');

  -- Flag skal være ikke-tomme strenge.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',30,30,0,14,%L,'ocr_uncertain','clause_segment_v1',%L,%L,1,'record_text','[1,{}]')$q$,
    v_occ, substr(v_text,1,14), v_run, v_parent),
    'EVIDENCE_CLAUSE_FLAGS_INVALID');
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',30,30,0,14,%L,'ocr_uncertain','clause_segment_v1',%L,%L,1,'record_text','["  "]')$q$,
    v_occ, substr(v_text,1,14), v_run, v_parent),
    'EVIDENCE_CLAUSE_FLAGS_INVALID');

  -- Positiv: arvet kvalitet, versioneret regel, gyldige flag.
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,
    parent_observation_id,clause_ordinal,clause_classification,clause_flags)
  VALUES(v_occ,'clause',30,30,0,14,substr(v_text,1,14),'ocr_uncertain','clause_segment_v1/2026-09-10',v_run,v_parent,1,'record_text','["ocr_uncertain_span"]');

  RAISE NOTICE 't5 clause provenance OK';
END $t5_clause_provenance$;

ROLLBACK;
