-- Kontrakttest for writer-operationen `interpretation_proposal` (#147 dagsværk 4.4).
--
-- RØD FØRST: uden DDL'en skal den fejle med REIMPORT_WRITER_AUTHORIZATION_INVALID.
--
-- BEMÆRK hvad der IKKE testes her: relations-claims uden identificerbar modpart
-- ("NN.", "4 sønner") afvises i MANIFEST-BUILDEREN, ikke i writeren. Ét
-- writer-element er én record, så en exception for ét claim ruller hele recorden
-- tilbage — præcis den fejl, projektejeren afgjorde imod efter 4.3b's bundt 1,
-- hvor ét ugyldigt claim fældede seks korrekte. Alt, der kan afgøres før
-- writeren, afgøres før writeren.
--
-- Kør:  psql -v ON_ERROR_STOP=1 -f tests/sql/test-interpretation-proposal.sql

\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.expect_error(p_token text, p_sql text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE p_token||'%' THEN
      RAISE EXCEPTION 'PROPOSAL_TEST_WRONG_ERROR: expected % got %', p_token, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'PROPOSAL_TEST_NO_ERROR: expected %', p_token;
END $$;

-- Fixture: source, run, rendition, occurrence, helpost, to klausuler og en persona.
-- Teksten er opdigtet.
CREATE FUNCTION pg_temp.fixture() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_source bigint := -147401; v_run uuid := gen_random_uuid();
  v_rend uuid; v_occ uuid; v_parent uuid; v_c1 uuid; v_c2 uuid;
  v_rec uuid; v_persona uuid; v_mention uuid;
  v_t1 text := 'Testperson Opdigtsen, f. 1801 i Fiktivby.';
  v_t2 text := 'Blev 1825 kammerjunker.';
  v_text text := v_t1 || ' ' || v_t2;
BEGIN
  INSERT INTO public.source(id,slags,titel,udgave,aar)
  VALUES(v_source,'DAA-udgave','Proposal fixture','synthetic',1900) ON CONFLICT(id) DO NOTHING;

  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,
                                     profile_version,input_sha256,manifest)
  VALUES(v_run,v_source,'proposal-'||v_run::text,'fixture','fixture','fixture',repeat('1',64),'{}');

  INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata)
  VALUES(v_source,'prop-r-'||v_run::text,'pdf_text_layer',repeat('2',64),'{}') RETURNING id INTO v_rend;

  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,
    char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  VALUES(v_rend,'occ-1',10,10,100,100+char_length(v_text),v_text,repeat('3',64),repeat('4',64),v_run)
  RETURNING id INTO v_occ;

  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,
    char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id)
  VALUES(v_occ,'person_post',10,10,100,100+char_length(v_text),v_text,'clear','fixture',v_run)
  RETURNING id INTO v_parent;

  -- To klausuler under helposten.
  INSERT INTO private.source_observation(occurrence_id,parent_observation_id,clause_ordinal,
    observation_kind,page_from,page_to,char_from,char_to,post_char_from,post_char_to,
    verbatim_text,quality_status,extraction_method,clause_flags,extraction_run_id)
  VALUES(v_occ,v_parent,1,'record_text',10,10,100,100+char_length(v_t1),0,char_length(v_t1),
         v_t1,'clear','clause_segment_v1',ARRAY[]::text[],v_run) RETURNING id INTO v_c1;
  INSERT INTO private.source_observation(occurrence_id,parent_observation_id,clause_ordinal,
    observation_kind,page_from,page_to,char_from,char_to,post_char_from,post_char_to,
    verbatim_text,quality_status,extraction_method,clause_flags,extraction_run_id)
  VALUES(v_occ,v_parent,2,'record_text',10,10,100+char_length(v_t1)+1,100+char_length(v_text),
         char_length(v_t1)+1,char_length(v_text),
         v_t2,'clear','clause_segment_v1',ARRAY[]::text[],v_run) RETURNING id INTO v_c2;

  RETURN jsonb_build_object('source',v_source,'run',v_run,'occ',v_occ,'parent',v_parent,
                            'c1',v_c1,'c2',v_c2,
                            'h1',encode(extensions.digest(v_t1,'sha256'),'hex'),
                            'h2',encode(extensions.digest(v_t2,'sha256'),'hex'));
END $$;


-- ---------------------------------------------------------------------------
-- 1. Operationen skal findes i writerens lukkede mængder
-- ---------------------------------------------------------------------------
DO $t1_operation_known$
BEGIN
  IF to_regprocedure('private.write_interpretation_proposal(jsonb,uuid)') IS NULL
     AND to_regprocedure('private.write_interpretation_proposal(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_AUTHORIZATION_INVALID: write_interpretation_proposal mangler';
  END IF;
  IF to_regprocedure('public.red_apply_reimport_interpretation_proposal(jsonb,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_AUTHORIZATION_INVALID: wrapperen mangler';
  END IF;
END $t1_operation_known$;


-- ---------------------------------------------------------------------------
-- 2. deterministic_uuid: fast testvektor + determinisme
-- ---------------------------------------------------------------------------
DO $t2_deterministic_uuid$
DECLARE a uuid; b uuid;
BEGIN
  IF to_regprocedure('private.deterministic_uuid(text)') IS NULL THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_AUTHORIZATION_INVALID: deterministic_uuid mangler';
  END IF;
  a := private.deterministic_uuid('daa-4.4-testvektor');
  b := private.deterministic_uuid('daa-4.4-testvektor');
  IF a IS DISTINCT FROM b THEN
    RAISE EXCEPTION 'PROPOSAL_UUID_NOT_DETERMINISTIC';
  END IF;
  -- Versionsnibble 5 og RFC 4122-variantbits, som spec §7.1 foreskriver.
  -- (Konstruktionen er projektets egen, ikke en RFC-konform v5 — se funktionens
  --  egen kommentar. Testen fastholder blot den valgte form.)
  IF substring(a::text from 15 for 1) <> '5' THEN
    RAISE EXCEPTION 'PROPOSAL_UUID_VERSION_NIBBLE: fik %', substring(a::text from 15 for 1);
  END IF;
  IF substring(a::text from 20 for 1) NOT IN ('8','9','a','b') THEN
    RAISE EXCEPTION 'PROPOSAL_UUID_VARIANT_BITS: fik %', substring(a::text from 20 for 1);
  END IF;
  IF private.deterministic_uuid('daa-4.4-testvektor-x') = a THEN
    RAISE EXCEPTION 'PROPOSAL_UUID_COLLIDES_ON_DIFFERENT_INPUT';
  END IF;
END $t2_deterministic_uuid$;


-- ---------------------------------------------------------------------------
-- 3. Positive: principal med én klausul, principal med flere, other
-- ---------------------------------------------------------------------------
DO $t3_positive$
DECLARE fx jsonb;
BEGIN
  fx := pg_temp.fixture();
  -- Placeholder indtil writeren findes: rejser det samme token som ovenfor,
  -- så testen er rød af den rigtige grund, før DDL'en skrives.
  IF to_regprocedure('private.write_interpretation_proposal(jsonb,uuid)') IS NULL
     AND to_regprocedure('private.write_interpretation_proposal(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_AUTHORIZATION_INVALID: kan ikke køre positive blokke';
  END IF;
END $t3_positive$;


-- ---------------------------------------------------------------------------
-- 4. Negative, én pr. afvisningsgrund fra spec §7.1
--
--    Hver skal give sit EGET token. En fælles fejlbesked ville skjule, hvilken
--    regel der bed — og så kan man ikke se, om værnet virker eller blot fejler.
-- ---------------------------------------------------------------------------
DO $t4_negative$
DECLARE fx jsonb;
BEGIN
  IF to_regprocedure('private.write_interpretation_proposal(jsonb,uuid)') IS NULL
     AND to_regprocedure('private.write_interpretation_proposal(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_AUTHORIZATION_INVALID: kan ikke køre negative blokke';
  END IF;
  fx := pg_temp.fixture();
  -- Dækkes når writeren findes:
  --   REIMPORT_WRITER_CLAUSE_UNKNOWN          ukendt ordinal
  --   REIMPORT_WRITER_CLAUSE_HASH_MISMATCH    ordinal findes, hash afviger
  --   REIMPORT_WRITER_CLAUSE_FOREIGN_POST     klausul under en anden helpost
  --   REIMPORT_WRITER_PREDICATE_INACTIVE      prædikat ikke aktivt i 5.1
  --   REIMPORT_WRITER_VALUE_KIND_INVALID      værdi passer ikke til value_kind
  --   REIMPORT_WRITER_CONFIDENCE_INVALID      confidence uden for [0,1]
  --   REIMPORT_WRITER_PRINCIPAL_WITHOUT_PERSONA
  --   REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS
END $t4_negative$;


ROLLBACK;
