-- Trin 6a: seedede reimport_writer_profile-rækker afprøves med deres nøjagtige værdier.
-- Kræver en base hvor source 3 og source 1 findes og db-migrations.sql er kørt (CI-trin efter bootstrap; trinnet
-- indsætter source 1 før migrationerne, som i prod).
\set ON_ERROR_STOP on
BEGIN;
DO $seed_1939_clause$
DECLARE r private.reimport_writer_profile%ROWTYPE; v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM private.reimport_writer_profile WHERE profile_id='daa-1939-clause-evidence-v1';
  IF v_n<>1 THEN RAISE EXCEPTION 'SEED_1939_CLAUSE_ROW_COUNT: %', v_n; END IF;
  SELECT * INTO r FROM private.reimport_writer_profile WHERE profile_id='daa-1939-clause-evidence-v1';
  IF r.source_id<>3 OR r.profile_version<>'clause-evidence-v1' THEN RAISE EXCEPTION 'SEED_1939_CLAUSE_IDENTITY'; END IF;
  IF r.writer_config IS DISTINCT FROM '{"run_key_prefix":"reimport-clause-evidence-1939:","schema_version":"clause-evidence-manifest-v1","extractor_version":"clause-evidence-v1","rendition_key":"daa-1939-calamari-r6-clean","rendition_kind":"ocr_text","rendition_metadata":{"edition":"1939"},"observation_extraction_method":"clause_segment_v1","citation_label_template":"DAA 1939 side {page_from}","text_form":"raw","helpost_observation_kind":"person"}'::jsonb THEN
    RAISE EXCEPTION 'SEED_1939_CLAUSE_CONFIG';
  END IF;
  IF r.profile_sha256<>private.reimport_canonical_json_sha256(r.writer_config)
     OR r.profile_sha256<>'2aa5a358063fdf98f19954a683279cc3cabfd3eb5d5dd9c7fdaf5e42571b66d7' THEN RAISE EXCEPTION 'SEED_1939_CLAUSE_SHA: %', r.profile_sha256; END IF;
  IF NOT private.validate_reimport_writer_config(r.writer_config) THEN RAISE EXCEPTION 'SEED_1939_CLAUSE_INVALID'; END IF;
  RAISE NOTICE 'seed 1939 clause profile OK';
END $seed_1939_clause$;
DO $seed_2018_20_source_text_revision$
DECLARE r private.reimport_writer_profile%ROWTYPE; v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM private.reimport_writer_profile WHERE profile_id='daa-2018-20-source-text-revision-v1';
  IF v_n<>1 THEN RAISE EXCEPTION 'SEED_2018_20_STR_ROW_COUNT: %', v_n; END IF;
  SELECT * INTO r FROM private.reimport_writer_profile WHERE profile_id='daa-2018-20-source-text-revision-v1';
  IF r.source_id<>1 OR r.profile_version<>'source-text-revision-v1' THEN RAISE EXCEPTION 'SEED_2018_20_STR_IDENTITY'; END IF;
  IF r.writer_config IS DISTINCT FROM '{"citation_label_template":"DAA 2018-20 side {page_from}","extractor_version":"source-text-revision-v1","helpost_observation_kind":"person_post","observation_extraction_method":"clause_segment_v1","rendition_key":"daa-2018-20-pdftotext-r1","rendition_kind":"pdf_text_layer","rendition_metadata":{"edition":"2018-20","pdf_sha256":"3beadfc15e3fa1a4090589af56cd4e95599a9231e8f979dfb60c4e27bbd8252a","pdftotext_version":"26.07.0"},"run_key_prefix":"reimport-source-text-revision:","schema_version":"source-text-revision-manifest-v1","text_form":"folded_projection@page_header"}'::jsonb THEN
    RAISE EXCEPTION 'SEED_2018_20_STR_CONFIG';
  END IF;
  IF r.profile_sha256<>private.reimport_canonical_json_sha256(r.writer_config)
     OR r.profile_sha256<>'60c7deaa352a3d7916ef35aba160a8f602c931474dd093a0dd1d6873d0a16f45' THEN RAISE EXCEPTION 'SEED_2018_20_STR_SHA: %', r.profile_sha256; END IF;
  IF NOT private.validate_reimport_writer_config(r.writer_config) THEN RAISE EXCEPTION 'SEED_2018_20_STR_INVALID'; END IF;
  RAISE NOTICE 'seed 2018-20 source text revision profile OK';
END $seed_2018_20_source_text_revision$;
ROLLBACK;
