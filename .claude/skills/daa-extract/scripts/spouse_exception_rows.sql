-- Trin 5b 2b-i (spec §5.1): rækkefil til undtagelsesarket. Indeholder navne og bogens tekst → 0600 under
-- ~/.private/5b-2b-i/. Kør:  PGCLIENTENCODING=UTF8 psql -XAtq -v source=1 -f spouse_exception_rows.sql > rows.json
-- Rækkefilen er præcis projektionens ::text + én LF; arkets script genberegner de samme bytes (spec §5.3).
\set ON_ERROR_STOP on
SET default_transaction_read_only=on;
SET TimeZone='UTC';
SET search_path=pg_catalog,public,private;
SELECT private.spouse_exception_projection(:source)::text;
