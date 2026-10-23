-- 5a+5b-skridt `disposition` (writer; plan B1 Task 3a). Manifestet regenereres i basen af
-- private.relation_disposition_input(src) (dets citing_interpretation_ids er basens tilfældige versions-id'er); items
-- nøgles: observation, fra-version, aktørerne som persona_key og de citerende fortolkninger som <key>#<version>. Ved match
-- skrives manifestet til :manifest (kalderen har umask 077) og relation_batch_apply.sql køres med det (writerens to
-- transaktioner; fejlkrogen fault=after_authorize ligger mellem dem). 0 elementer ⇒ ingen batch.
-- Brug: psql -v src=<kilde> -v mode=capture|replay -v items=<sti> -v manifest=<sti> [-v fault=after_authorize]
--       -f transfer_5ab_step_disposition.sql
\set t5_step disposition
\if :{?manifest}
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_USAGE: -v manifest mangler'; END $$;
\endif
\ir transfer_5ab_step_begin.sql
SELECT private.relation_disposition_input(:src)::text AS t5_manifest \gset
SELECT set_config('daa.t5_items', coalesce((SELECT jsonb_agg(x ORDER BY x->>'observation_id' COLLATE "C") FROM (
  SELECT jsonb_build_object('observation_id', e.value->>'observation_id',
    'from_disposition_version', (e.value->>'from_disposition_version')::integer,
    'actor_persona_keys', (SELECT coalesce(jsonb_agg(sp.persona_key ORDER BY sp.persona_key COLLATE "C"), '[]')
                             FROM jsonb_array_elements_text(e.value->'actor_persona_ids') a JOIN private.source_persona sp ON sp.id=a::uuid),
    'citing_interpretations', (SELECT coalesce(jsonb_agg(i.interpretation_key||'#'||i.version ORDER BY i.interpretation_key::text COLLATE "C", i.version), '[]')
                             FROM jsonb_array_elements_text(e.value->'citing_interpretation_ids') c JOIN private.interpretation i ON i.id=c::uuid)) x
    FROM jsonb_each(:'t5_manifest'::jsonb->'authorized_elements') e) s), '[]')::text, true) \g /dev/null
SELECT jsonb_array_length(current_setting('daa.t5_items')::jsonb) AS t5_n, jsonb_array_length(current_setting('daa.t5_items')::jsonb)>0 AS t5_do \gset
\ir transfer_5ab_step_items.sql
\ir transfer_5ab_step_compare.sql
\o :manifest
SELECT :'t5_manifest';
\o
COMMIT;
\if :t5_do
\set source_id :src
\set operation relation_disposition
\set manifest_file :manifest
\set actor :t5_actor
\o /dev/null
\ir relation_batch_apply.sql
\o
\endif
\if :t5_replay
\else
\set t5_mv `/bin/mv -- :'t5_items_tmp' :'items' && echo ok`
SELECT :'t5_mv'='ok' AS t5_mv_ok \gset
\if :t5_mv_ok
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_ITEMS_RENAME'; END $$;
\endif
\endif
\echo STEP_OK :t5_step n=:t5_n items_sha256=:t5_sha
