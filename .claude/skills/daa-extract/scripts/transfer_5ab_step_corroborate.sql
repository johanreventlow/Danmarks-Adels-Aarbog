-- 5a+5b-skridt `corroborate` (hash_gated; plan B1 Task 3b). family_corroboration på kontrolkørslen: i capture kildens
-- seneste, i replay den, pakkens control_key (kandidatkørslens run_key) peger på. Mængden beregnes som ejer som
-- corr_set (schema.sql:16494-16505); set_sha256 genberegnes i basen. items = {control_key, personas: [persona_key]}.
-- Brug: psql -v src=<kilde> -v mode=capture|replay -v items=<sti> [-v fault=before_commit] -f transfer_5ab_step_corroborate.sql
\set t5_step corroborate
\ir transfer_5ab_step_begin.sql
\if :t5_replay
SELECT current_setting('daa.t5_pack_items')::jsonb->>'control_key' AS t5_want \gset
\else
\set t5_want ''
\endif
-- Altid én række (max over højst én); NULL fjerner variablen, så en manglende kørsel giver koden, ikke en \gset-fejl.
SELECT max(x.ctl) AS t5_ctl, max(x.run) AS t5_run, max(x.k) AS t5_ckey FROM (
  SELECT c.id::text ctl, r.id::text run, r.input_sha256||':'||r.config_sha256 k
    FROM private.identity_control_run c JOIN private.source_persona_identity_candidate_run r ON r.id=c.candidate_run_id
   WHERE c.source_id=:src AND (:'t5_want'='' OR r.input_sha256||':'||r.config_sha256=:'t5_want')
   ORDER BY r.run_seq DESC LIMIT 1) x \gset
\if :{?t5_ctl}
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_RUN_MISSING'; END $$;
\endif
-- Kun en bestået kontrol må bekræfte: ved status failed skriver RPC'en en failed-hændelse og returnerer 0 uden fejl
-- (schema.sql: red_corroborate_family_identities), så en fejlet kontrol ellers ville blive bagt ind i pakken som STEP_OK.
SELECT max(s.status)='passed' AS t5_passed FROM private.control_run_status(:'t5_ctl'::uuid) s \gset
\if :t5_passed
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_CONTROL_NOT_PASSED'; END $$;
\endif
WITH corr AS (
  SELECT c.source_persona_id pid FROM private.source_persona_identity_candidate c
    LEFT JOIN private.source_persona_identity i ON i.source_persona_id=c.source_persona_id
   WHERE c.run_id=:'t5_run'::uuid AND c.rank=1 AND (c.basis->>'corroboration_eligible')::boolean IS TRUE
     AND (i.source_persona_id IS NULL OR i.decision_status='proposed')
     AND NOT EXISTS (SELECT 1 FROM private.identity_control_sample x WHERE x.control_run_id=:'t5_ctl'::uuid AND x.source_persona_id=c.source_persona_id)
     AND NOT EXISTS (SELECT 1 FROM private.identity_control_exclusion x WHERE x.control_run_id=:'t5_ctl'::uuid AND x.source_persona_id=c.source_persona_id))
SELECT private.reimport_canonical_json_sha256(coalesce((SELECT jsonb_agg(pid::text ORDER BY pid::text COLLATE "C") FROM corr), '[]'::jsonb)) AS t5_set,
       (SELECT count(*) FROM corr) AS t5_n,
       set_config('daa.t5_items', jsonb_build_object('control_key', :'t5_ckey', 'personas',
         coalesce((SELECT jsonb_agg(sp.persona_key ORDER BY sp.persona_key COLLATE "C") FROM corr JOIN private.source_persona sp ON sp.id=corr.pid), '[]'))::text,
         true) AS t5_i \gset
\ir transfer_5ab_step_items.sql
\ir transfer_5ab_step_compare.sql
SET LOCAL ROLE authenticated;
SELECT public.red_corroborate_family_identities(:'t5_ctl'::uuid, :'t5_set') AS t5_ret \gset
RESET ROLE;
SELECT :t5_ret=:t5_n AS t5_ret_ok \gset
\if :t5_ret_ok
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_ITEMS_MISMATCH corroborate'; END $$;
\endif
\ir transfer_5ab_step_end.sql
