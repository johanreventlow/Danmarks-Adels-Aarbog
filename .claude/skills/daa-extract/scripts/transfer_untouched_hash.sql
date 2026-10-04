-- Uberørt-hash (spec §5 »Uberørt«). Som transfer_restore_hash.sql MINUS de tabeller overførslen
-- skriver i (writer, afgørelser, bindinger) og sekvenser ejet af dem. Listen er hardkodet her og
-- dermed bundet af GO-inventaret. Output: daa.untouched_hash.
-- Pinner sessionsindstillinger (TimeZone, extra_float_digits, IntervalStyle, DateStyle, search_path, row_security) under beregningen,
-- så hashen er ens lokalt og i prod (Supabase = UTC), og gendanner kalderens værdier bagefter. search_path=pg_catalog:
-- alle objekter i filen er skemakvalificerede (public./private./extensions.).
DO $uh$
DECLARE
  v_tz text:=current_setting('TimeZone'); v_efd text:=current_setting('extra_float_digits'); v_is text:=current_setting('IntervalStyle');
  v_ds text:=current_setting('DateStyle'); v_sp text:=current_setting('search_path'); v_rs text:=current_setting('row_security');
       r record; h text; acc text := '';
        excl text[] := ARRAY['private.reimport_writer_profile','private.reimport_authorization','private.reimport_batch',
                             'private.reimport_event','private.extraction_run','private.interpretation',
                             'private.interpretation_observation','private.clause_disposition',
                             'private.interpretation_promotion_batch','private.interpretation_promotion'];
BEGIN
  PERFORM set_config('TimeZone','UTC',false); PERFORM set_config('extra_float_digits','1',false); PERFORM set_config('IntervalStyle','postgres',false);
  PERFORM set_config('DateStyle','ISO, MDY',false); PERFORM set_config('search_path','pg_catalog',false);
  PERFORM set_config('row_security','off',false);  -- en rolle under RLS skal fejle, ikke filtrere lydløst
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
  PERFORM set_config('TimeZone',v_tz,false); PERFORM set_config('extra_float_digits',v_efd,false); PERFORM set_config('IntervalStyle',v_is,false);
  PERFORM set_config('DateStyle',v_ds,false); PERFORM set_config('search_path',v_sp,false); PERFORM set_config('row_security',v_rs,false);
END $uh$;
SELECT current_setting('daa.untouched_hash') AS untouched_hash;
