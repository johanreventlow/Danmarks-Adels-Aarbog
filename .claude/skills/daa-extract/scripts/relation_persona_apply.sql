-- Trin 5b: autorisér, åbn, skriv, finalisér én relation_persona-batch. Printer kun tal og hashes.
-- Variabler: actor, source_id, manifest_file, profile_file. Profilen oprettes som ejer (idempotent).
\set ON_ERROR_STOP on
\set content `cat :manifest_file`
SELECT private.reimport_canonical_json_sha256((:'content'::jsonb)->'authorized_elements') AS m \gset
-- Profilfilen (-v profile_file, fx ../profiles/relation-persona-<udgave>.json) bærer writer-profilens id, version og
-- writer_config; scriptet har ingen udgave i sin logik (trin 6d-3).
\if :{?profile_file}
\else
DO $$ BEGIN RAISE EXCEPTION 'RELATION_PROFILE_FILE_REQUIRED: -v profile_file mangler'; END $$;
\endif
\set profile_json `cat -- :'profile_file'`
SELECT p->>'profile_id' AS profile_id, p->>'profile_version' AS profile_version, (p->'writer_config')::text AS cfg,
       coalesce(jsonb_typeof(p->'writer_config')='object' AND coalesce(btrim(p->>'profile_id'),'')<>''
         AND coalesce(btrim(p->>'profile_version'),'')<>'',false) AS profile_ok
  FROM (SELECT :'profile_json'::jsonb AS p) x \gset
\if :profile_ok
\else
DO $$ BEGIN RAISE EXCEPTION 'RELATION_PROFILE_FILE_INVALID'; END $$;
\endif
INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
VALUES (:source_id,:'profile_id',:'profile_version',private.reimport_canonical_json_sha256(:'cfg'::jsonb),:'cfg'::jsonb)
ON CONFLICT (source_id,profile_id) DO NOTHING;
-- Codex 6d-3 T2: en eksisterende profilrække skal svare til filen (version, konfiguration og hash); ellers ville
-- autorisationen bruge databasens konfiguration, mens filen dokumenterer en anden. Rækken ændres aldrig.
SELECT profile_sha256 AS profile_sha,
       (profile_version=:'profile_version' AND writer_config=:'cfg'::jsonb
        AND profile_sha256=private.reimport_canonical_json_sha256(:'cfg'::jsonb)) AS profile_match
  FROM private.reimport_writer_profile WHERE source_id=:source_id AND profile_id=:'profile_id' \gset
\if :profile_match
\else
DO $$ BEGIN RAISE EXCEPTION 'RELATION_PROFILE_FILE_DRIFT: profilrækken i databasen svarer ikke til profilfilen'; END $$;
\endif
SELECT jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text AS dbid \gset
-- Autorisationen er kun tildelt service_role (schema.sql:4558) — egen transaktion, som i
-- docs/runbooks/legacy-migration-reimport-rehearsal.md §3.
BEGIN;
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \g /dev/null
SELECT public.red_authorize_reimport(:'m',:'m',:'dbid',:source_id,:'profile_id',:'profile_sha',
  (:'content'::jsonb)->'expected_counts',(:'content'::jsonb)->'authorized_elements',gen_random_uuid(),
  clock_timestamp()+interval '1 hour') AS auth \gset
COMMIT;
-- Begin, apply og finalize som authenticated redaktion.
BEGIN;
SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \g /dev/null
SET LOCAL ROLE authenticated;
SELECT public.red_begin_reimport(:'auth'::uuid,:'m',:'m') AS batch \gset
SELECT count(public.red_apply_reimport_relation_persona(:'batch'::uuid,e.key,e.value)) AS skrevet
  FROM jsonb_each((:'content'::jsonb)->'authorized_elements') e;
SELECT public.red_finalize_reimport(:'batch'::uuid)->'counts' AS counts;
SELECT r->'relation_results' AS relation_results FROM public.red_reimport_batch_result(:'auth'::uuid,:'batch'::uuid) r;
COMMIT;
SELECT 'manifest_sha256 '||:'m' AS manifest;
