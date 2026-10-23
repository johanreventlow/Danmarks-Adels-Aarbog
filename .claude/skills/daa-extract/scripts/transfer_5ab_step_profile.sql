-- 5a+5b-skridt `profile` (sql; plan B1 Task 3a, errata: profilen før første writer, så et afbrud mellem profil og
-- autorisation ikke giver MIXED). Indsætter writer-profilen relation-persona-2018-20 / relation-persona-v1 med
-- konfigurationen fra relation_persona_apply.sql:6, ON CONFLICT DO NOTHING. items = [{profile_id, profile_sha256}].
-- Brug: psql -v src=<kilde> -v mode=capture|replay -v items=<sti> [-v fault=before_commit] -f transfer_5ab_step_profile.sql
\set t5_step profile
\ir transfer_5ab_step_begin.sql
SELECT '{"citation_label_template":"DAA 2018-20 s. {page_from}","extractor_version":"relation-persona-v1","observation_extraction_method":"relation_persona_extract","rendition_key":"relation-persona","rendition_kind":"pdf_text_layer","rendition_metadata":{},"run_key_prefix":"relation-persona","schema_version":"relation-persona-v1"}' AS t5_cfg \gset
SELECT set_config('daa.t5_items', jsonb_build_array(jsonb_build_object('profile_id','relation-persona-2018-20',
  'profile_sha256',private.reimport_canonical_json_sha256(:'t5_cfg'::jsonb)))::text, true) \g /dev/null
\ir transfer_5ab_step_items.sql
\ir transfer_5ab_step_compare.sql
WITH ins AS (
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES (:src,'relation-persona-2018-20','relation-persona-v1',private.reimport_canonical_json_sha256(:'t5_cfg'::jsonb),:'t5_cfg'::jsonb)
  ON CONFLICT (source_id,profile_id) DO NOTHING RETURNING 1)
SELECT count(*) AS t5_n FROM ins \gset
\ir transfer_5ab_step_end.sql
