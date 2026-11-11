-- 5a+5b-skridt `profile` (sql; plan B1 Task 3a, errata: profilen før første writer, så et afbrud mellem profil og
-- autorisation ikke giver MIXED). Indsætter writer-profilen fra profilfilen (-v profile_file; samme fil som
-- relation_persona_apply.sql og relation_batch_apply.sql læser), ON CONFLICT DO NOTHING. items = [{profile_id, profile_sha256}].
-- Brug: psql -v src=<kilde> -v mode=capture|replay -v items=<sti> -v profile_file=<sti> [-v fault=before_commit]
--       -f transfer_5ab_step_profile.sql
\set t5_step profile
\ir transfer_5ab_step_begin.sql
\if :{?profile_file}
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_USAGE: -v profile_file mangler'; END $$;
\endif
\set t5_profile_json `cat -- :'profile_file'`
SELECT p->>'profile_id' AS t5_profile_id, p->>'profile_version' AS t5_profile_version, (p->'writer_config')::text AS t5_cfg,
       coalesce(jsonb_typeof(p->'writer_config')='object' AND coalesce(btrim(p->>'profile_id'),'')<>''
         AND coalesce(btrim(p->>'profile_version'),'')<>'',false) AS t5_profile_ok
  FROM (SELECT :'t5_profile_json'::jsonb AS p) x \gset
\if :t5_profile_ok
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_PROFILE_FILE_INVALID'; END $$;
\endif
SELECT set_config('daa.t5_items', jsonb_build_array(jsonb_build_object('profile_id',:'t5_profile_id',
  'profile_sha256',private.reimport_canonical_json_sha256(:'t5_cfg'::jsonb)))::text, true) \g /dev/null
\ir transfer_5ab_step_items.sql
\ir transfer_5ab_step_compare.sql
WITH ins AS (
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES (:src,:'t5_profile_id',:'t5_profile_version',private.reimport_canonical_json_sha256(:'t5_cfg'::jsonb),:'t5_cfg'::jsonb)
  ON CONFLICT (source_id,profile_id) DO NOTHING RETURNING 1)
SELECT count(*) AS t5_n FROM ins \gset
-- Codex 6d-3 T2: en eksisterende profilrække skal svare til filen; ellers kvitterede skridtet filens hash, mens
-- databasen beholdt en anden konfiguration. Rækken ændres aldrig; skridtet afbrydes før COMMIT.
SELECT coalesce((SELECT profile_version=:'t5_profile_version' AND writer_config=:'t5_cfg'::jsonb
         AND profile_sha256=private.reimport_canonical_json_sha256(:'t5_cfg'::jsonb)
    FROM private.reimport_writer_profile WHERE source_id=:src AND profile_id=:'t5_profile_id'),false) AS t5_profile_match \gset
\if :t5_profile_match
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_PROFILE_FILE_DRIFT: profilrækken i databasen svarer ikke til profilfilen'; END $$;
\endif
\ir transfer_5ab_step_end.sql
