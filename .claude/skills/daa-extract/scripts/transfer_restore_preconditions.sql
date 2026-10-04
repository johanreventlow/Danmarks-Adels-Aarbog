-- Restore-forudsætninger (spec §6.1 trin 2, review runde 2 N2). Læse-kun.
-- (1) Forældreløse rækker pr. enkeltkolonne-FK i private+public: en restore kan ikke genskabe en
--     FK over forældreløse rækker. Flerkolonne-FK'er tælles som antal (skal stå i rapporten).
-- (2) Katalogfingeraftryk (spec §6.1): alle constraints (pg_get_constraintdef, alle typer), ikke-interne
--     triggere (pg_get_triggerdef + aktiveringstilstand), RLS-flag pr. tabel (relrowsecurity,
--     relforcerowsecurity), policies (permissive, roller, kommando, udtryk), funktions- og
--     sekvensdefinitioner i private+public — sammenlignes med prods eget efter fortrydelsesøvelsen.
--     Output: daa.restore_preconditions.
-- Pinner sessionsindstillinger (TimeZone, extra_float_digits, IntervalStyle, DateStyle, search_path, row_security) under beregningen,
-- så hashen er ens lokalt og i prod (Supabase = UTC), og gendanner kalderens værdier bagefter. search_path=pg_catalog:
-- alle objekter i filen er skemakvalificerede (public./private./extensions.).
DO $pc$
DECLARE
  v_tz text:=current_setting('TimeZone'); v_efd text:=current_setting('extra_float_digits'); v_is text:=current_setting('IntervalStyle');
  v_ds text:=current_setting('DateStyle'); v_sp text:=current_setting('search_path'); v_rs text:=current_setting('row_security');
       r record; n bigint; orphans jsonb := '{}'; multi int := 0; cat text;
BEGIN
  PERFORM set_config('TimeZone','UTC',false); PERFORM set_config('extra_float_digits','1',false); PERFORM set_config('IntervalStyle','postgres',false);
  PERFORM set_config('DateStyle','ISO, MDY',false); PERFORM set_config('search_path','pg_catalog',false);
  PERFORM set_config('row_security','off',false);  -- en rolle under RLS skal fejle, ikke filtrere lydløst
  FOR r IN SELECT con.conname, cn.nspname AS sch, c.relname AS tab, a.attname AS col,
                  fn.nspname AS fsch, f.relname AS ftab, fa.attname AS fcol
             FROM pg_constraint con
             JOIN pg_class c ON c.oid = con.conrelid JOIN pg_namespace cn ON cn.oid = c.relnamespace
             JOIN pg_class f ON f.oid = con.confrelid JOIN pg_namespace fn ON fn.oid = f.relnamespace
             JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = con.conkey[1]
             JOIN pg_attribute fa ON fa.attrelid = f.oid AND fa.attnum = con.confkey[1]
            WHERE con.contype = 'f' AND cn.nspname IN ('private','public') AND array_length(con.conkey,1) = 1
            ORDER BY cn.nspname COLLATE "C", con.conname COLLATE "C" LOOP
    EXECUTE format('SELECT count(*) FROM %I.%I x WHERE x.%I IS NOT NULL AND NOT EXISTS (SELECT 1 FROM %I.%I y WHERE y.%I = x.%I)',
                   r.sch, r.tab, r.col, r.fsch, r.ftab, r.fcol, r.col) INTO n;
    IF n > 0 THEN orphans := orphans || jsonb_build_object(r.sch || '.' || r.conname, n); END IF;
  END LOOP;
  SELECT count(*) INTO multi FROM pg_constraint con JOIN pg_namespace cn ON cn.oid = con.connamespace
   WHERE con.contype = 'f' AND cn.nspname IN ('private','public') AND array_length(con.conkey,1) > 1;
  SELECT string_agg(t, E'\n' ORDER BY t COLLATE "C") INTO cat FROM (
    SELECT 'con:' || contype::text || ':' || conrelid::regclass::text || ':' || conname || ':' || pg_get_constraintdef(oid) AS t
      FROM pg_constraint WHERE conrelid <> 0 AND connamespace IN (SELECT oid FROM pg_namespace WHERE nspname IN ('private','public'))
    UNION ALL SELECT 'trg:' || tg.tgrelid::regclass::text || ':' || tg.tgname || ':' || tg.tgenabled::text || ':' || pg_get_triggerdef(tg.oid)
      FROM pg_trigger tg JOIN pg_class c ON c.oid = tg.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE NOT tg.tgisinternal AND n.nspname IN ('private','public')
    UNION ALL SELECT 'rls:' || n.nspname || '.' || c.relname || ':' || c.relrowsecurity::text || ':' || c.relforcerowsecurity::text
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind IN ('r','p') AND n.nspname IN ('private','public')
    UNION ALL SELECT 'policy:' || schemaname || '.' || tablename || ':' || policyname || ':' || permissive || ':' ||
           coalesce((SELECT string_agg(rn, ',' ORDER BY rn COLLATE "C") FROM unnest(roles::text[]) AS u(rn)), '') || ':' || cmd || ':' ||
           coalesce(qual,'') || ':' || coalesce(with_check,'')
      FROM pg_policies WHERE schemaname IN ('private','public')
    UNION ALL SELECT 'fn:' || n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || '):' || md5(pg_get_functiondef(p.oid))
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('private','public') AND p.prokind IN ('f','p')
    UNION ALL SELECT 'seq:' || n.nspname || '.' || c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind = 'S' AND n.nspname IN ('private','public')
  ) s;
  PERFORM set_config('daa.restore_preconditions', jsonb_build_object(
    'orphans', orphans,
    'n_orphans_total', coalesce((SELECT sum(value::bigint) FROM jsonb_each_text(orphans)), 0),
    'n_multi_column_fks', multi,
    'catalog_sha256', encode(extensions.digest(convert_to(coalesce(cat,''),'UTF8'),'sha256'),'hex'))::text, false);
  PERFORM set_config('TimeZone',v_tz,false); PERFORM set_config('extra_float_digits',v_efd,false); PERFORM set_config('IntervalStyle',v_is,false);
  PERFORM set_config('DateStyle',v_ds,false); PERFORM set_config('search_path',v_sp,false); PERFORM set_config('row_security',v_rs,false);
END $pc$;
SELECT current_setting('daa.restore_preconditions') AS restore_preconditions;
