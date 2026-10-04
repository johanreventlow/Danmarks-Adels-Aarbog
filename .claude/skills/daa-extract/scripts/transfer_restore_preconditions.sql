-- Restore-forudsætninger (spec §6.1 trin 2, review runde 2 N2). Læse-kun.
-- (1) Forældreløse rækker pr. enkeltkolonne-FK i private+public: en restore kan ikke genskabe en
--     FK over forældreløse rækker. Flerkolonne-FK'er tælles som antal (skal stå i rapporten).
-- (2) Katalogfingeraftryk: FK-, policy-, funktions- og sekvensdefinitioner — sammenlignes med
--     prods eget efter fortrydelsesøvelsen. Output: daa.restore_preconditions.
DO $pc$
DECLARE r record; n bigint; orphans jsonb := '{}'; multi int := 0; cat text;
BEGIN
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
    SELECT 'fk:' || conrelid::regclass::text || ':' || conname || ':' || pg_get_constraintdef(oid) AS t
      FROM pg_constraint WHERE contype = 'f' AND connamespace IN (SELECT oid FROM pg_namespace WHERE nspname IN ('private','public'))
    UNION ALL SELECT 'policy:' || schemaname || '.' || tablename || ':' || policyname || ':' || coalesce(qual,'') || ':' || coalesce(with_check,'')
      FROM pg_policies WHERE schemaname IN ('private','public')
    UNION ALL SELECT 'fn:' || n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || '):' || md5(pg_get_functiondef(p.oid))
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('private','public') AND p.prokind IN ('f','p')
    UNION ALL SELECT 'seq:' || sequence_schema || '.' || sequence_name FROM information_schema.sequences WHERE sequence_schema IN ('private','public')
  ) s;
  PERFORM set_config('daa.restore_preconditions', jsonb_build_object(
    'orphans', orphans,
    'n_orphans_total', coalesce((SELECT sum(value::bigint) FROM jsonb_each_text(orphans)), 0),
    'n_multi_column_fks', multi,
    'catalog_sha256', encode(extensions.digest(convert_to(coalesce(cat,''),'UTF8'),'sha256'),'hex'))::text, false);
END $pc$;
SELECT current_setting('daa.restore_preconditions') AS restore_preconditions;
