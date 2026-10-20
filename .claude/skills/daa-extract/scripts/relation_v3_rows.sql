-- Trin 5b 2b-ii runde 2 (spec §17.6): rækkefil til ægteskabsark v3 (med helpost og P-rækker). Indeholder navne og bogens tekst → 0600 under
-- ~/.private/5b-navneregel-v3/. Kør:  PGCLIENTENCODING=UTF8 psql -XAtq -v actor=… -v source=1 -f relation_v3_rows.sql > rows.json
-- Rækkefilen er præcis projektionens ::text + én LF.
\set ON_ERROR_STOP on
BEGIN;
SET TRANSACTION READ ONLY;
SET LOCAL TimeZone='UTC';
SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \g /dev/null
SET LOCAL ROLE authenticated;
SELECT public.red_relation_persona_v3_input(:source)::text;
ROLLBACK;
