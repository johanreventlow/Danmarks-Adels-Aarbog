-- 5a+5b-skridt `control` (sql; plan B1 Task 3b). red_register_identity_control_run på en kandidatkørsel: i capture kildens
-- seneste (run_seq), i replay den, pakkens run_key (input_sha256:config_sha256) peger på. Kontrolkørslens indhold er
-- RPC'ens output, så items sammenlignes efter kaldet og før COMMIT (en afvigelse ruller kaldet tilbage).
-- items = {run_key, cause, populationshashes, k_random, n_samples, n_exclusions, n_parent_cards}.
-- Brug: psql -v src=<kilde> -v mode=capture|replay -v items=<sti> [-v cause=<tekst>] [-v fault=before_commit]
--       -f transfer_5ab_step_control.sql
\set t5_step control
\ir transfer_5ab_step_begin.sql
\if :t5_replay
SELECT current_setting('daa.t5_pack_items')::jsonb->>'run_key' AS t5_want, current_setting('daa.t5_pack_items')::jsonb->>'cause' AS t5_cause \gset
\else
\set t5_want ''
\if :{?cause}
\set t5_cause :cause
\endif
\endif
-- Altid én række (max over højst én); NULL fjerner variablen, så en manglende kørsel giver koden, ikke en \gset-fejl.
SELECT max(x.id) AS t5_run, max(x.k) AS t5_runkey FROM (
  SELECT r.id::text id, r.input_sha256||':'||r.config_sha256 k FROM private.source_persona_identity_candidate_run r
   WHERE r.source_id=:src AND (:'t5_want'='' OR r.input_sha256||':'||r.config_sha256=:'t5_want')
   ORDER BY r.run_seq DESC LIMIT 1) x \gset
\if :{?t5_run}
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_RUN_MISSING'; END $$;
\endif
\if :{?t5_cause}
\else
\set t5_cause ''
\endif
SET LOCAL ROLE authenticated;
SELECT public.red_register_identity_control_run(:'t5_run'::uuid, nullif(:'t5_cause','')) AS t5_ctl \gset
RESET ROLE;
SELECT set_config('daa.t5_items', jsonb_build_object('run_key', :'t5_runkey', 'cause', c.cause,
    'identity_population_sha256', c.identity_population_sha256, 'relation_population_sha256', c.relation_population_sha256,
    'input_list_sha256', c.input_list_sha256, 'excluded_sha256', c.excluded_sha256, 'k_random', c.k_random,
    'n_samples', (SELECT count(*) FROM private.identity_control_sample s WHERE s.control_run_id=c.id),
    'n_exclusions', (SELECT count(*) FROM private.identity_control_exclusion x WHERE x.control_run_id=c.id),
    'n_parent_cards', (SELECT count(*) FROM private.identity_control_parent_card p WHERE p.control_run_id=c.id))::text, true),
       (SELECT count(*) FROM private.identity_control_sample s WHERE s.control_run_id=c.id) AS t5_n
  FROM private.identity_control_run c WHERE c.id=:'t5_ctl'::uuid \g /dev/null
SELECT (current_setting('daa.t5_items')::jsonb->>'n_samples')::integer AS t5_n \gset
\ir transfer_5ab_step_items.sql
\ir transfer_5ab_step_compare.sql
\ir transfer_5ab_step_end.sql
