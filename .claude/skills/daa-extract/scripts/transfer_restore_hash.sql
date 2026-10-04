-- Restore-hash (spec §4.3 »ingen skrivning siden dumpet«; §6.1 trin 4b). Læse-kun.
-- Alle ordinære tabeller og sekvenser i private+public. Ingen PK-antagelse: rækker sorteres på
-- deres egen to_jsonb-tekst. Output: daa.restore_hash.
DO $rh$
DECLARE r record; h text; acc text := '';
BEGIN
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
END $rh$;
SELECT current_setting('daa.restore_hash') AS restore_hash;
