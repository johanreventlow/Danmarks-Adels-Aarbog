-- Restore-hash (spec §4.3 »ingen skrivning siden dumpet«; §6.1 trin 4b). Læse-kun.
-- Alle ordinære tabeller og sekvenser i private+public. Ingen PK-antagelse: rækker sorteres på
-- deres egen to_jsonb-tekst. Output: daa.restore_hash.
-- Pinner sessionsindstillinger (TimeZone, extra_float_digits, IntervalStyle, DateStyle, search_path) under beregningen,
-- så hashen er ens lokalt og i prod (Supabase = UTC), og gendanner kalderens værdier bagefter. search_path=pg_catalog:
-- alle objekter i filen er skemakvalificerede (public./private./extensions.).
DO $rh$
DECLARE
  v_tz text:=current_setting('TimeZone'); v_efd text:=current_setting('extra_float_digits'); v_is text:=current_setting('IntervalStyle');
  v_ds text:=current_setting('DateStyle'); v_sp text:=current_setting('search_path');
       r record; h text; acc text := '';
BEGIN
  PERFORM set_config('TimeZone','UTC',false); PERFORM set_config('extra_float_digits','1',false); PERFORM set_config('IntervalStyle','postgres',false);
  PERFORM set_config('DateStyle','ISO, MDY',false); PERFORM set_config('search_path','pg_catalog',false);
  FOR r IN SELECT n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname IN ('private','public') AND c.relkind IN ('r','p')
            ORDER BY n.nspname COLLATE "C", c.relname COLLATE "C" LOOP
    EXECUTE format('SELECT encode(extensions.digest(convert_to(coalesce(string_agg(t, E''\n'' ORDER BY t COLLATE "C"),''''),''UTF8''),''sha256''),''hex'') FROM (SELECT to_jsonb(x)::text AS t FROM %I.%I x) s',
                   r.nspname, r.relname) INTO h;
    acc := acc || r.nspname || '.' || r.relname || '=' || h || E'\n';
  END LOOP;
  FOR r IN SELECT n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname IN ('private','public') AND c.relkind = 'S'
            ORDER BY n.nspname COLLATE "C", c.relname COLLATE "C" LOOP
    EXECUTE format('SELECT last_value::text || '':'' || is_called::text FROM %I.%I', r.nspname, r.relname) INTO h;
    acc := acc || 'seq:' || r.nspname || '.' || r.relname || '=' || h || E'\n';
  END LOOP;
  PERFORM set_config('daa.restore_hash', encode(extensions.digest(convert_to(acc,'UTF8'),'sha256'),'hex'), false);
  PERFORM set_config('TimeZone',v_tz,false); PERFORM set_config('extra_float_digits',v_efd,false); PERFORM set_config('IntervalStyle',v_is,false);
  PERFORM set_config('DateStyle',v_ds,false); PERFORM set_config('search_path',v_sp,false);
END $rh$;
SELECT current_setting('daa.restore_hash') AS restore_hash;
