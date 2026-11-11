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
-- Trin 6b: publikationsprofilen er klausulprofilens config med egen run-nøgle, extractor_version og persona_key_prefix; ingen anden profils hash ændres.
DO $profile_1939_publication$
DECLARE r private.reimport_writer_profile%ROWTYPE; v_expected jsonb; v_clause jsonb; v_n int; k record;
BEGIN
  SELECT count(*) INTO v_n FROM private.reimport_writer_profile WHERE profile_id='daa-1939-publication-v1';
  IF v_n<>1 THEN RAISE EXCEPTION 'PUBLICATION_REG_PROFILE_ROW_COUNT: %',v_n; END IF;
  SELECT * INTO r FROM private.reimport_writer_profile WHERE profile_id='daa-1939-publication-v1';
  IF r.source_id<>3 OR r.profile_version<>'publication-v1' THEN RAISE EXCEPTION 'PUBLICATION_REG_PROFILE_IDENTITY'; END IF;
  SELECT writer_config INTO v_clause FROM private.reimport_writer_profile WHERE profile_id='daa-1939-clause-evidence-v1';
  v_expected:=(v_clause-'run_key_prefix'-'extractor_version')||'{"run_key_prefix":"reimport-publication:","extractor_version":"publication-v1","persona_key_prefix":"1939:"}'::jsonb;
  IF r.writer_config IS DISTINCT FROM v_expected THEN RAISE EXCEPTION 'PUBLICATION_REG_PROFILE_CONFIG'; END IF;
  IF r.profile_sha256<>private.reimport_canonical_json_sha256(r.writer_config) THEN RAISE EXCEPTION 'PUBLICATION_REG_PROFILE_SHA'; END IF;
  IF NOT private.validate_reimport_writer_config(r.writer_config) THEN RAISE EXCEPTION 'PUBLICATION_REG_PROFILE_INVALID'; END IF;
  -- hashes taget fra main før ændringen (trin 6b); 2018-20-profilen kontrolleres, hvor kilde 1 findes
  FOR k IN SELECT * FROM (VALUES
      ('daa-1939-v50-production-write-v1','25349caff16f2c13002a4950e80fe8697ffcf49e196dbcd9d1550919caf52fd3',true),
      ('daa-1939-clause-evidence-v1','2aa5a358063fdf98f19954a683279cc3cabfd3eb5d5dd9c7fdaf5e42571b66d7',true),
      ('daa-2018-20-source-text-revision-v1','60c7deaa352a3d7916ef35aba160a8f602c931474dd093a0dd1d6873d0a16f45',false)
    ) AS t(profile_id,sha,required) LOOP
    SELECT count(*) INTO v_n FROM private.reimport_writer_profile WHERE profile_id=k.profile_id;
    IF v_n=0 AND k.required THEN RAISE EXCEPTION 'PUBLICATION_REG_PROFILE_MISSING: %',k.profile_id; END IF;
    IF v_n>1 OR EXISTS(SELECT 1 FROM private.reimport_writer_profile WHERE profile_id=k.profile_id AND profile_sha256<>k.sha) THEN
      RAISE EXCEPTION 'PUBLICATION_REG_PROFILE_SHA_CHANGED: %',k.profile_id; END IF;
  END LOOP;
  RAISE NOTICE 'OK: publication profile';
END $profile_1939_publication$;

-- Trin 6c-1: 1939's forslagsprofil er 2018-20-forslagsprofilens config med 1939's rendition/citation og helpost-slags
-- person (filen references/reimport-profiles/daa-1939-interpretation-proposal-v1.json giver samme config og hash).
DO $seed_1939_proposal$
DECLARE r private.reimport_writer_profile%ROWTYPE; v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM private.reimport_writer_profile WHERE profile_id='daa-1939-interpretation-proposal-v1';
  IF v_n<>1 THEN RAISE EXCEPTION 'SEED_1939_PROPOSAL_ROW_COUNT: %', v_n; END IF;
  SELECT * INTO r FROM private.reimport_writer_profile WHERE profile_id='daa-1939-interpretation-proposal-v1';
  IF r.source_id<>3 OR r.profile_version<>'1.0.0' THEN RAISE EXCEPTION 'SEED_1939_PROPOSAL_IDENTITY'; END IF;
  IF r.writer_config IS DISTINCT FROM '{"citation_label_template":"DAA 1939 side {page_from}","extractor_version":"interpretation-proposal-v1","helpost_observation_kind":"person","observation_extraction_method":"clause_segment_v1","rendition_key":"daa-1939-calamari-r6-clean","rendition_kind":"ocr_text","rendition_metadata":{"edition":"1939"},"run_key_prefix":"reimport-interpretation-proposal:","schema_version":"interpretation-proposal-manifest-v1"}'::jsonb THEN
    RAISE EXCEPTION 'SEED_1939_PROPOSAL_CONFIG';
  END IF;
  IF r.profile_sha256<>private.reimport_canonical_json_sha256(r.writer_config)
     OR r.profile_sha256<>'c6131dcc9655fd74abeb3de787592ee76a7fa17944a9b525b41a38bdd7acd6dc' THEN RAISE EXCEPTION 'SEED_1939_PROPOSAL_SHA: %', r.profile_sha256; END IF;
  IF NOT private.validate_reimport_writer_config(r.writer_config) THEN RAISE EXCEPTION 'SEED_1939_PROPOSAL_INVALID'; END IF;
  RAISE NOTICE 'seed 1939 proposal profile OK';
END $seed_1939_proposal$;

-- persona_key_prefix er valgfri, men skal være en ikke-tom streng
DO $persona_key_prefix$
DECLARE v_cfg jsonb;
BEGIN
  SELECT writer_config INTO v_cfg FROM private.reimport_writer_profile WHERE profile_id='daa-1939-publication-v1';
  IF NOT private.validate_reimport_writer_config(v_cfg) OR NOT private.validate_reimport_writer_config(v_cfg-'persona_key_prefix') THEN
    RAISE EXCEPTION 'PERSONA_KEY_PREFIX_VALID_REJECTED'; END IF;
  IF private.validate_reimport_writer_config(v_cfg||'{"persona_key_prefix":""}'::jsonb)
     OR private.validate_reimport_writer_config(v_cfg||'{"persona_key_prefix":1}'::jsonb)
     OR private.validate_reimport_writer_config(v_cfg||'{"persona_key_prefix":null}'::jsonb) THEN
    RAISE EXCEPTION 'PERSONA_KEY_PREFIX_INVALID_ACCEPTED'; END IF;
  RAISE NOTICE 'OK: persona_key_prefix';
END $persona_key_prefix$;

-- Trin 6d-3 (spec §5.1.1): relationsprofilerne seedes for kilde 1 og 3 med netop de aftalte former og tekstform.
DO $seed_relation_persona_profiles$
DECLARE v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM private.relation_persona_profile WHERE source_id IN (1,3);
  IF v_n<>4 THEN RAISE EXCEPTION 'SEED_RELATION_PROFILE_ROW_COUNT: %', v_n; END IF;
  IF (SELECT jsonb_object_agg(profile||'@'||source_id,jsonb_build_object('forms',predicate_forms,'text_form',text_form))
        FROM private.relation_persona_profile WHERE source_id IN (1,3))
     IS DISTINCT FROM '{"relation-persona-2018-20-v1@1":{"forms":{"relation.marriage":"v1","relation.child":"v1","relation.parent":"v1"},"text_form":"folded"},
                       "relation-persona-2018-20-v2@1":{"forms":{"relation.marriage":"v2"},"text_form":"folded"},
                       "relation-persona-2018-20-v3@1":{"forms":{"relation.marriage":"v3"},"text_form":"folded"},
                       "relation-persona-1939-v1@3":{"forms":{"relation.marriage":"v3","relation.parent":"v1"},"text_form":"raw"}}'::jsonb THEN
    RAISE EXCEPTION 'SEED_RELATION_PROFILE_VALUES';
  END IF;
  RAISE NOTICE 'seed relation persona profiles OK';
END $seed_relation_persona_profiles$;

ROLLBACK;
