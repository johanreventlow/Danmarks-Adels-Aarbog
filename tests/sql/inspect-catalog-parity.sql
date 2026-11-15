-- Katalogparitet (kodereview 36, D1): hele kataloget for skemaerne public og private, én linje pr. objekt
-- (art|nøgle|detaljer). Kaldes på en ren schema.sql-base og på migrerede baser; tests/sql/check-catalog-parity.sh
-- sammenligner. Dækker funktioner (definition, SECURITY DEFINER, config, EXECUTE-rettigheder), tabeller og views
-- (RLS, rettigheder, options), kolonner, constraints, indekser, triggere, politikker, view-definitioner, sekvenser,
-- enum-/domænetyper og skemarettigheder. Rettigheder vises kun for PUBLIC, anon, authenticated og service_role, så
-- ejer- og grantornavne ikke afhænger af, hvem der byggede basen. Udvidelsers egne objekter er udeladt.
\set ON_ERROR_STOP on
WITH ns AS (
  SELECT oid, nspname FROM pg_namespace WHERE nspname IN ('public','private')
), ext AS (
  SELECT objid FROM pg_depend WHERE deptype = 'e'
), acl(o, a) AS (
  SELECT NULL::oid, NULL::aclitem[] WHERE false
), linjer AS (
  -- funktioner
  SELECT 'fn' AS art, p.oid::regprocedure::text AS noegle,
         concat_ws('|', p.prosecdef, coalesce(array_to_string(p.proconfig, ','), ''),
           coalesce((SELECT string_agg(CASE WHEN r.grantee = 0 THEN 'PUBLIC' ELSE r.grantee::regrole::text END || ':' || r.privilege_type, ',' ORDER BY 1) FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) r WHERE r.grantee = 0 OR r.grantee::regrole::text IN ('anon','authenticated','service_role')), ''),
           md5(pg_get_functiondef(p.oid))) AS detalje
    FROM pg_proc p JOIN ns ON ns.oid = p.pronamespace
   WHERE p.prokind IN ('f','p','w') AND p.oid NOT IN (SELECT objid FROM ext)
  UNION ALL
  SELECT 'agg', p.oid::regprocedure::text, ''
    FROM pg_proc p JOIN ns ON ns.oid = p.pronamespace WHERE p.prokind = 'a'
  UNION ALL
  -- relationer (tabeller, views, sekvenser, matviews)
  SELECT 'rel', c.oid::regclass::text,
         concat_ws('|', c.relkind, c.relrowsecurity, c.relforcerowsecurity, c.relpersistence,
           coalesce((SELECT string_agg(CASE WHEN r.grantee = 0 THEN 'PUBLIC' ELSE r.grantee::regrole::text END || ':' || r.privilege_type, ',' ORDER BY 1) FROM aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) r WHERE r.grantee = 0 OR r.grantee::regrole::text IN ('anon','authenticated','service_role')), ''),
           coalesce(array_to_string(c.reloptions, ','), ''))
    FROM pg_class c JOIN ns ON ns.oid = c.relnamespace
   WHERE c.relkind IN ('r','p','v','m','S','f') AND c.oid NOT IN (SELECT objid FROM ext)
  UNION ALL
  -- kolonner
  SELECT 'col', c.oid::regclass::text || '.' || a.attname,
         concat_ws('|', format_type(a.atttypid, a.atttypmod), a.attnotnull,
           coalesce(pg_get_expr(d.adbin, d.adrelid), ''), a.attidentity, a.attgenerated,
           coalesce(co.collname, ''),
           coalesce((SELECT string_agg(CASE WHEN r.grantee = 0 THEN 'PUBLIC' ELSE r.grantee::regrole::text END || ':' || r.privilege_type, ',' ORDER BY 1) FROM aclexplode(a.attacl) r WHERE r.grantee = 0 OR r.grantee::regrole::text IN ('anon','authenticated','service_role')), ''))
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN ns ON ns.oid = c.relnamespace
    LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    LEFT JOIN pg_collation co ON co.oid = a.attcollation AND a.attcollation <> 0
         AND co.oid <> (SELECT oid FROM pg_collation WHERE collname = 'default')
   WHERE c.relkind IN ('r','p','v','m','f') AND a.attnum > 0 AND NOT a.attisdropped
     AND c.oid NOT IN (SELECT objid FROM ext)
  UNION ALL
  -- constraints
  SELECT 'con', coalesce(c.conrelid::regclass::text, c.contypid::regtype::text) || '.' || c.conname,
         concat_ws('|', c.contype, c.condeferrable, c.condeferred, c.convalidated, pg_get_constraintdef(c.oid))
    FROM pg_constraint c JOIN ns ON ns.oid = c.connamespace
  UNION ALL
  -- indekser (inkl. dem bag constraints)
  SELECT 'idx', i.indexrelid::regclass::text, pg_get_indexdef(i.indexrelid)
    FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid JOIN ns ON ns.oid = c.relnamespace
  UNION ALL
  -- triggere
  SELECT 'trg', t.tgrelid::regclass::text || '.' || t.tgname, concat_ws('|', t.tgenabled, pg_get_triggerdef(t.oid))
    FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN ns ON ns.oid = c.relnamespace
   WHERE NOT t.tgisinternal
  UNION ALL
  -- politikker
  SELECT 'pol', pl.polrelid::regclass::text || '.' || pl.polname,
         concat_ws('|', pl.polcmd, pl.polpermissive,
           (SELECT string_agg(CASE WHEN r = 0 THEN 'public' ELSE r::regrole::text END, ',' ORDER BY 1)
              FROM unnest(pl.polroles) r),
           coalesce(pg_get_expr(pl.polqual, pl.polrelid), ''), coalesce(pg_get_expr(pl.polwithcheck, pl.polrelid), ''))
    FROM pg_policy pl JOIN pg_class c ON c.oid = pl.polrelid JOIN ns ON ns.oid = c.relnamespace
  UNION ALL
  -- views: definitionen
  SELECT 'vdef', c.oid::regclass::text, md5(pg_get_viewdef(c.oid))
    FROM pg_class c JOIN ns ON ns.oid = c.relnamespace WHERE c.relkind IN ('v','m')
  UNION ALL
  -- sekvenser
  SELECT 'seq', s.seqrelid::regclass::text,
         concat_ws('|', format_type(s.seqtypid, NULL), s.seqstart, s.seqincrement, s.seqmax, s.seqmin, s.seqcycle)
    FROM pg_sequence s JOIN pg_class c ON c.oid = s.seqrelid JOIN ns ON ns.oid = c.relnamespace
  UNION ALL
  -- typer: enum-værdier og domæner
  SELECT 'type', t.oid::regtype::text,
         concat_ws('|', t.typtype,
           (SELECT string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder) FROM pg_enum e WHERE e.enumtypid = t.oid),
           CASE WHEN t.typtype = 'd' THEN format_type(t.typbasetype, t.typtypmod) END)
    FROM pg_type t JOIN ns ON ns.oid = t.typnamespace
   WHERE t.typtype IN ('e','d') AND t.oid NOT IN (SELECT objid FROM ext)
  UNION ALL
  -- skemaernes rettigheder
  SELECT 'nsp', n.nspname,
         coalesce((SELECT string_agg(CASE WHEN r.grantee = 0 THEN 'PUBLIC' ELSE r.grantee::regrole::text END || ':' || r.privilege_type, ',' ORDER BY 1) FROM aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) r WHERE r.grantee = 0 OR r.grantee::regrole::text IN ('anon','authenticated','service_role')), '')
    FROM pg_namespace n JOIN ns ON ns.oid = n.oid
)
SELECT l FROM (SELECT regexp_replace(art || '|' || noegle || '|' || detalje, '\s*\n\s*', ' ', 'g') AS l FROM linjer) x ORDER BY l COLLATE "C";
