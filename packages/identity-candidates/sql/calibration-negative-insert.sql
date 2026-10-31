-- Trin 6b (plan Task 10/15): registrerer negativkontrollens kandidatkørsel fra en ÆNDRET inputkopi direkte i
-- kørselstabellerne. KUN i en dedikeret kalibreringsbase: red_record_identity_candidates afviser bevidst en kopi
-- (IDENTITY_CANDIDATE_INPUT_DRIFT), og en ekstra kørsel med samme config gør en rigtig kørsel forældet for
-- publication_identity (PUBLICATION_IDENTITY_RUN_STALE). Indsættelsen er ellers RPC'ens: indholds-id'er af samme
-- nøgler, config-, input- og kandidathashes, persona- og kandidatantal og familiekontekstens hash.
-- Kræver superbruger eller ejer af private-skemaet (ingen RLS-vej) og -v kalibreringsbase=ja.
-- Brug: psql -X -q -d <kalibreringsbase> -v kalibreringsbase=ja -v actor=<redaktør-uuid> -v cand_file=<fil> -f …
\set ON_ERROR_STOP on
\if :{?kalibreringsbase}
\else
  \set kalibreringsbase ''
\endif
SELECT set_config('cal.base', :'kalibreringsbase', false) IS NOT NULL AS ok \g /dev/null
DO $$ BEGIN
  IF current_setting('cal.base')<>'ja' THEN RAISE EXCEPTION 'CALIBRATION_BASE_REQUIRED'; END IF;
END $$;
\set content `cat :cand_file`
BEGIN;
SELECT coalesce(j->'run'->>'input_sha256','') ~ '^[0-9a-f]{64}$' AS cal_sha_ok,
       EXISTS (SELECT 1 FROM private.source_persona_identity_candidate_run r WHERE r.source_id=(j->'run'->>'source_id')::bigint
                AND r.input_sha256=j->'run'->>'input_sha256'
                AND r.config_sha256=private.reimport_canonical_json_sha256(j->'run'->'config')) AS cal_run_exists
  FROM (SELECT :'content'::jsonb AS j) c \gset
SELECT set_config('cal.sha_ok', :'cal_sha_ok', true), set_config('cal.run_exists', :'cal_run_exists', true) \g /dev/null
DO $$ BEGIN
  IF current_setting('cal.sha_ok')<>'t' THEN RAISE EXCEPTION 'CALIBRATION_INPUT_SHA_MISSING'; END IF;
  IF current_setting('cal.run_exists')<>'f' THEN RAISE EXCEPTION 'CALIBRATION_RUN_EXISTS'; END IF;
END $$;
WITH c AS (SELECT :'content'::jsonb AS j),
run AS (
  INSERT INTO private.source_persona_identity_candidate_run(
    id,source_id,generator_version,config,config_sha256,input_spec,input_sha256,candidates_sha256,
    persona_count,candidate_count,created_by,created_by_name)
  SELECT private.content_uuid('identity-candidate-run',jsonb_build_object('source_id',(j->'run'->>'source_id')::bigint,
           'input_sha256',j->'run'->>'input_sha256','config_sha256',private.reimport_canonical_json_sha256(j->'run'->'config'))),
         (j->'run'->>'source_id')::bigint, j->'run'->>'generator_version', j->'run'->'config',
         private.reimport_canonical_json_sha256(j->'run'->'config'), j->'run'->'input_spec', j->'run'->>'input_sha256',
         private.reimport_canonical_json_sha256(j->'candidates'), jsonb_array_length(j->'run'->'input_spec'->'persona_ids'),
         jsonb_array_length(j->'candidates'), :'actor'::uuid, 'kalibrering-negativkontrol'
    FROM c RETURNING id)
INSERT INTO private.source_persona_identity_candidate(id,run_id,source_persona_id,candidate_person_id,rank,score,tier,basis,
                                                      family_context_sha256)
SELECT private.content_uuid('identity-candidate',jsonb_build_object('run_id',run.id,'source_persona_id',(x->>'source_persona_id')::uuid,
         'candidate_person_id',(x->>'candidate_person_id')::bigint)),
       run.id,(x->>'source_persona_id')::uuid,(x->>'candidate_person_id')::bigint,(x->>'rank')::int,(x->>'score')::numeric,
       x->>'tier',x->'basis',
       (SELECT CASE WHEN fc IS NULL THEN NULL ELSE private.reimport_canonical_json_sha256(fc) END
          FROM private.persona_family_context((x->>'source_persona_id')::uuid) fc)
  FROM run, c, jsonb_array_elements(c.j->'candidates') x;
COMMIT;
