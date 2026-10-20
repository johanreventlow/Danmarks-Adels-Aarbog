-- Trin 5b 2b-iii (spec 2026-10-20 §6): rækkefil til børnearket. Indeholder navne og bogens tekst → 0600 under
-- ~/.private/5b-2b-iii/. Kør:  PGCLIENTENCODING=UTF8 psql -XAtq -v actor=… -v source=1 -f relation_child_rows.sql > rows.json
-- Rækkefilen er præcis projektionens ::text + én LF.
\set ON_ERROR_STOP on
BEGIN;
SET TRANSACTION READ ONLY;
SET LOCAL TimeZone='UTC';
SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \g /dev/null
SET LOCAL ROLE authenticated;
SELECT public.red_relation_child_sheet_input(:source)::text;
ROLLBACK;
