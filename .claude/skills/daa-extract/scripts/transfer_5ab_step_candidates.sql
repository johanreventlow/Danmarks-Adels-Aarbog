-- 5a+5b-skridt `candidates` (hash_gated; plan B1 Task 3b). Kandidatfilen (generatorens output {run, candidates}; pakkens
-- input i begge tilstande) skrives via red_record_identity_candidates; input_sha256 genberegnes i basen og erstatter
-- filens. items = {run_key: <basens input_sha256>:<config_sha256>, generator_version, candidates_sha256, n}. Erstatter
-- write-candidates.sql, der ekkoede kørslens id.
-- Brug: psql -v src=<kilde> -v mode=capture|replay -v items=<sti> -v input=<kandidatfil> [-v fault=before_commit]
--       -f transfer_5ab_step_candidates.sql
\set t5_step candidates
\if :{?input}
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_USAGE: -v input mangler'; END $$;
\endif
\ir transfer_5ab_step_begin.sql
\set t5_cand `cat :input`
SELECT ((:'t5_cand'::jsonb)#>>'{run,source_id}')::bigint IS DISTINCT FROM :src::bigint AS t5_wrong_src \gset
\if :t5_wrong_src
DO $$ BEGIN RAISE EXCEPTION 'STEP_USAGE: kandidatfilen er for en anden kilde'; END $$;
\endif
SELECT private.reimport_canonical_json_sha256(private.identity_candidate_input(:src, (:'t5_cand'::jsonb)#>'{run,input_spec}')) AS t5_input_sha \gset
SELECT set_config('daa.t5_items', jsonb_build_object(
    'run_key', :'t5_input_sha'||':'||private.reimport_canonical_json_sha256((:'t5_cand'::jsonb)#>'{run,config}'),
    'generator_version', (:'t5_cand'::jsonb)#>>'{run,generator_version}',
    'candidates_sha256', private.reimport_canonical_json_sha256((:'t5_cand'::jsonb)->'candidates'),
    'n', jsonb_array_length((:'t5_cand'::jsonb)->'candidates'))::text, true) \g /dev/null
SELECT jsonb_array_length((:'t5_cand'::jsonb)->'candidates') AS t5_n \gset
\ir transfer_5ab_step_items.sql
\ir transfer_5ab_step_compare.sql
SET LOCAL ROLE authenticated;
SELECT public.red_record_identity_candidates(jsonb_set((:'t5_cand'::jsonb)->'run', '{input_sha256}', to_jsonb(:'t5_input_sha'::text)),
  (:'t5_cand'::jsonb)->'candidates') \g /dev/null
RESET ROLE;
\ir transfer_5ab_step_end.sql
