\set ON_ERROR_STOP on
\set content `cat :cand_file`
BEGIN;
SELECT set_config('request.jwt.claim.sub', :'actor', true);
SET LOCAL ROLE authenticated;
SELECT red_record_identity_candidates((:'content'::jsonb)->'run', (:'content'::jsonb)->'candidates') AS run_id;
COMMIT;
