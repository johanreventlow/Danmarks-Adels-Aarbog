-- Kører rækkeeksporten og lægger dens output, byte for byte som psql -A -t skriver det, i GUC'en t6.rows.
-- \i har sin egen forespørgselsbuffer, så outputtet fanges via en midlertidig fil (mktemp, 0600), som slettes igen.
-- Filen kan byttes med psql-variablen rows_sql (standard: repo'ets interpretation_control_rows.sql). Kaldes fra
-- repo-roden af test-interpretation-control-classification.sql (trin 6c-2 Task 6).
\if :{?rows_sql}
\else
\set rows_sql .claude/skills/daa-extract/scripts/interpretation_control_rows.sql
\endif
\set t6_quiet :QUIET
\set QUIET on
\pset format unaligned
\pset tuples_only on
\set t6_rows_file `mktemp`
\o :t6_rows_file
\i :rows_sql
\o
\set t6_rows `cat :t6_rows_file`
\! rm -f :t6_rows_file
\pset format aligned
\pset tuples_only off
\set QUIET :t6_quiet
SELECT set_config('t6.rows', :'t6_rows', true) \g /dev/null
