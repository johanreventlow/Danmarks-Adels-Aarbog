-- Tabelhashes (5a+5b-overførslen, plan A Task 1, invariant I8). Læse-kun.
-- Én linje »schema.tabel=<sha256>« pr. ordinær/partitioneret tabel i public/private, sorteret COLLATE "C".
-- Rækkerne hashes som to_jsonb(t)::text sorteret COLLATE "C" på hele teksten (ingen lokale-afhængig nøgleorden;
-- jsonb sorterer selv nøglerne, så kolonnerækkefølge efter ADD COLUMN er ligegyldig).
-- Med -v omit=<nøgle>[,<nøgle>…] fjernes nøglerne fra hver række (fx created_at, der får DEFAULT now() ved hver apply).
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SET LOCAL search_path TO pg_catalog;
SET LOCAL TimeZone='UTC';
SET LOCAL DateStyle='ISO, MDY';
SET LOCAL IntervalStyle='postgres';
SET LOCAL extra_float_digits=1;
SET LOCAL row_security=off;
\if :{?omit}
SELECT set_config('daa.th_omit', :'omit', true) \gset th_
\else
SELECT set_config('daa.th_omit', '', true) \gset th_
\endif
DO $th$
DECLARE r record; h text; acc text:=''; v_omit text:=current_setting('daa.th_omit');
BEGIN
  FOR r IN SELECT n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p')
            ORDER BY n.nspname COLLATE "C", c.relname COLLATE "C" LOOP
    EXECUTE format('SELECT encode(sha256(convert_to(coalesce(string_agg(t, E''\n'' ORDER BY t COLLATE "C"),''''),''UTF8'')),''hex'')
                      FROM (SELECT (to_jsonb(x) - %L::text[])::text AS t FROM %I.%I x) s', string_to_array(v_omit,','), r.nspname, r.relname) INTO h;
    acc:=acc||r.nspname||'.'||r.relname||'='||h||E'\n';
  END LOOP;
  PERFORM set_config('daa.th_lines', acc, true);
END $th$;
SELECT l FROM regexp_split_to_table(rtrim(current_setting('daa.th_lines'),E'\n'),E'\n') l ORDER BY l COLLATE "C";
COMMIT;
