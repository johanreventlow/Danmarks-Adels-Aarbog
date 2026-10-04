-- Uberørt-hash (spec §5 »Uberørt«). Som transfer_restore_hash.sql MINUS de tabeller overførslen
-- skriver i (writer, afgørelser, bindinger) og sekvenser ejet af dem. Listen er hardkodet her og
-- dermed bundet af GO-inventaret. Output: daa.untouched_hash.
DO $uh$
DECLARE r record; h text; acc text := '';
        excl text[] := ARRAY['private.reimport_writer_profile','private.reimport_authorization','private.reimport_batch',
                             'private.reimport_event','private.extraction_run','private.interpretation',
                             'private.interpretation_observation','private.clause_disposition',
                             'private.interpretation_promotion_batch','private.interpretation_promotion'];
BEGIN
  FOR r IN SELECT n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname IN ('private','public') AND c.relkind IN ('r','p')
              AND (n.nspname || '.' || c.relname) <> ALL (excl)
            ORDER BY n.nspname COLLATE "C", c.relname COLLATE "C" LOOP
    EXECUTE format('SELECT encode(extensions.digest(convert_to(coalesce(string_agg(t, E''\n'' ORDER BY t COLLATE "C"),''''),''UTF8''),''sha256''),''hex'') FROM (SELECT to_jsonb(x)::text AS t FROM %I.%I x) s',
                   r.nspname, r.relname) INTO h;
    acc := acc || r.nspname || '.' || r.relname || '=' || h || E'\n';
  END LOOP;
  FOR r IN SELECT n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname IN ('private','public') AND c.relkind = 'S'
              AND NOT EXISTS (SELECT 1 FROM pg_depend d JOIN pg_class t ON t.oid = d.refobjid
                               JOIN pg_namespace tn ON tn.oid = t.relnamespace
                              WHERE d.objid = c.oid AND d.deptype IN ('a','i')
                                AND (tn.nspname || '.' || t.relname) = ANY (excl))
            ORDER BY n.nspname COLLATE "C", c.relname COLLATE "C" LOOP
    EXECUTE format('SELECT last_value::text || '':'' || is_called::text FROM %I.%I', r.nspname, r.relname) INTO h;
    acc := acc || 'seq:' || r.nspname || '.' || r.relname || '=' || h || E'\n';
  END LOOP;
  PERFORM set_config('daa.untouched_hash', encode(extensions.digest(convert_to(acc,'UTF8'),'sha256'),'hex'), false);
END $uh$;
SELECT current_setting('daa.untouched_hash') AS untouched_hash;
