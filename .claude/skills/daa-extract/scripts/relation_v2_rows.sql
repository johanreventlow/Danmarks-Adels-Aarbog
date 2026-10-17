-- Trin 5b 2b-ii (spec §5.1): rækkefil til ægteskabsarket. Indeholder navne og bogens tekst → 0600 under
-- ~/.private/5b-2b-ii/. Kør:  PGCLIENTENCODING=UTF8 psql -XAtq -v actor=… -v source=1 -f relation_v2_rows.sql > rows.json
-- Rækkefilen er præcis projektionens ::text + én LF.
\set ON_ERROR_STOP on
BEGIN;
SET TRANSACTION READ ONLY;
SET LOCAL TimeZone='UTC';
SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \g /dev/null
SET LOCAL ROLE authenticated;
SELECT public.red_relation_persona_v2_input(:source)::text;
ROLLBACK;
