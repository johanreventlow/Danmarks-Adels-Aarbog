-- #244 (spec §6): rækkefil til nummerarket. Indeholder navne → 0600 under ~/.private/244/.
-- Kør:  PGCLIENTENCODING=UTF8 psql -XAtq -v actor=… -v source=1 -f relation_ordinal_rows.sql > rows.json
-- Rækkefilen er præcis projektionens ::text + én LF.
\set ON_ERROR_STOP on
BEGIN;
SET TRANSACTION READ ONLY;
SET LOCAL TimeZone='UTC';
SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \g /dev/null
SET LOCAL ROLE authenticated;
SELECT public.red_marriage_ordinal_correction_input(:source)::text;
ROLLBACK;
