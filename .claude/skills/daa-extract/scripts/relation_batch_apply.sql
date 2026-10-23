-- Trin 5b 2b-ii: autorisér, åbn, skriv, finalisér én batch for relation_person_create eller relation_disposition.
-- Variabler: actor, source_id, manifest_file, operation. Profilen oprettes som ejer (idempotent).
-- Manifestet er projektionens output ({expected_counts, authorized_elements}). Printer kun tal og hashes.
\set ON_ERROR_STOP on
\set content `cat :manifest_file`
SELECT :'operation'='relation_person_create' AS is_rpc, :'operation'='relation_disposition' AS is_disp \gset
\if :is_rpc
\elif :is_disp
\else
  DO $$ BEGIN RAISE EXCEPTION 'RELATION_BATCH_OPERATION_INVALID'; END $$;
\endif
SELECT private.reimport_canonical_json_sha256((:'content'::jsonb)->'authorized_elements') AS m \gset
SELECT '{"citation_label_template":"DAA 2018-20 s. {page_from}","extractor_version":"relation-persona-v1","observation_extraction_method":"relation_persona_extract","rendition_key":"relation-persona","rendition_kind":"pdf_text_layer","rendition_metadata":{},"run_key_prefix":"relation-persona","schema_version":"relation-persona-v1"}'::jsonb AS cfg \gset
INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
VALUES (:source_id,'relation-persona-2018-20','relation-persona-v1',private.reimport_canonical_json_sha256(:'cfg'::jsonb),:'cfg'::jsonb)
ON CONFLICT (source_id,profile_id) DO NOTHING;
SELECT profile_sha256 AS profile_sha FROM private.reimport_writer_profile WHERE source_id=:source_id AND profile_id='relation-persona-2018-20' \gset
SELECT jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text AS dbid \gset
BEGIN;
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \g /dev/null
SELECT public.red_authorize_reimport(:'m',:'m',:'dbid',:source_id,'relation-persona-2018-20',:'profile_sha',
  (:'content'::jsonb)->'expected_counts',(:'content'::jsonb)->'authorized_elements',gen_random_uuid(),
  clock_timestamp()+interval '1 hour') AS auth \gset
COMMIT;
-- Fejlkrog (kun test; 5a+5b-skridtet disposition): afbrud mellem autorisationen og batchen.
\if :{?fault}
SELECT :'fault'='after_authorize' AS fault_aa \gset
\if :fault_aa
DO $$ BEGIN RAISE EXCEPTION 'STEP_FAULT after_authorize'; END $$;
\endif
\endif
BEGIN;
SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \g /dev/null
SET LOCAL ROLE authenticated;
SELECT public.red_begin_reimport(:'auth'::uuid,:'m',:'m') AS batch \gset
\if :is_rpc
SELECT count(public.red_apply_reimport_relation_person_create(:'batch'::uuid,e.key,e.value)) AS skrevet
  FROM jsonb_each((:'content'::jsonb)->'authorized_elements') e;
\else
SELECT count(public.red_apply_reimport_relation_disposition(:'batch'::uuid,e.key,e.value)) AS skrevet
  FROM jsonb_each((:'content'::jsonb)->'authorized_elements') e;
\endif
SELECT public.red_finalize_reimport(:'batch'::uuid)->'counts' AS counts;
SELECT r->'relation_results' AS relation_results FROM public.red_reimport_batch_result(:'auth'::uuid,:'batch'::uuid) r;
COMMIT;
SELECT 'manifest_sha256 '||:'m' AS manifest;
