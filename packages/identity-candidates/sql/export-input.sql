-- Trin 5a: generatorens input, bygget og hashet af serveren. Output indeholder navne:
-- skriv til en 0600-fil under ~/.private/5a/, læs den aldrig i en agent.
\set ON_ERROR_STOP on
SET default_transaction_read_only=on;
BEGIN;
SELECT set_config('request.jwt.claim.sub', :'actor', true);
SET LOCAL ROLE authenticated;
SELECT red_identity_candidate_input(:source_id,
  CASE WHEN :'mode'='undecided' THEN '{"mode":"undecided"}'::jsonb
       ELSE jsonb_build_object('mode','list','persona_ids',
              (SELECT jsonb_agg(x ORDER BY x) FROM unnest(string_to_array(:'personas',',')) x)) END);
COMMIT;
