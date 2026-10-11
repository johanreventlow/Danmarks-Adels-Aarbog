-- Trin 5b: udtrækkets input. Output indeholder navne → 0600-fil under ~/.private/5b/.
\set ON_ERROR_STOP on
SET default_transaction_read_only=on;
BEGIN;
SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \g /dev/null
SET LOCAL ROLE authenticated;
SELECT red_relation_persona_input(:source_id);
COMMIT;
