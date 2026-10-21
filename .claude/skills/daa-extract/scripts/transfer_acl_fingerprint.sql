-- ACL-fingeraftryk (5a+5b-overførslen, plan A Task 1). Læse-kun; ingen grantor og ingen ejer.
-- Linjer, sorteret COLLATE "C":
--   P|g|<art t/s/f/n>|<modtager>|<objekt>|<privilegium>  grants til PUBLIC/anon/authenticated/service_role på objekter
--                                                        i public/private (uden extension-ejede) og på de to skemaer
--   P|m|<rolle>|<regprocedure>|<0/1>                     has_function_privilege(rolle, fn, 'EXECUTE') for public-funktioner
--   L|d|<rolle>|<skema eller ->|<objtype>|<modtager>|<privilegium>  pg_default_acl (prod-lokal: kun prod mod prod)
-- Med -v mode=digest: »portable <sha256>« og »local <sha256>« (sha over delens linjer forbundet med \n).
\set ON_ERROR_STOP on
\if :{?mode}
\set digest true
\else
\set digest false
\endif
BEGIN READ ONLY;
SET LOCAL search_path TO pg_catalog;
SET LOCAL TimeZone='UTC';
SET LOCAL row_security=off;
WITH ns AS (SELECT oid, nspname FROM pg_namespace WHERE nspname IN ('public','private')),
ext AS (SELECT classid, objid FROM pg_depend WHERE deptype='e'),
who(oid, name) AS (
  SELECT 0::oid, 'PUBLIC' UNION ALL SELECT oid, rolname::text FROM pg_roles WHERE rolname IN ('anon','authenticated','service_role')),
l AS (
  SELECT 'P|g|'||CASE c.relkind WHEN 'S' THEN 's' ELSE 't' END||'|'||w.name||'|'||ns.nspname||'.'||c.relname||'|'||a.privilege_type AS x
    FROM pg_class c JOIN ns ON ns.oid=c.relnamespace,
         aclexplode(coalesce(c.relacl, acldefault(CASE c.relkind WHEN 'S' THEN 's' ELSE 'r' END::"char", c.relowner))) a
    JOIN who w ON w.oid=a.grantee
   WHERE c.relkind IN ('r','p','v','m','S','f')
     AND NOT EXISTS (SELECT 1 FROM ext WHERE ext.classid='pg_class'::regclass AND ext.objid=c.oid)
  UNION ALL
  SELECT 'P|g|f|'||w.name||'|'||p.oid::regprocedure::text||'|'||a.privilege_type
    FROM pg_proc p JOIN ns ON ns.oid=p.pronamespace,
         aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
    JOIN who w ON w.oid=a.grantee
   WHERE NOT EXISTS (SELECT 1 FROM ext WHERE ext.classid='pg_proc'::regclass AND ext.objid=p.oid)
  UNION ALL
  SELECT 'P|g|n|'||w.name||'|'||n.nspname||'|'||a.privilege_type
    FROM pg_namespace n, aclexplode(coalesce(n.nspacl, acldefault('n'::"char", n.nspowner))) a
    JOIN who w ON w.oid=a.grantee
   WHERE n.nspname IN ('public','private')
  UNION ALL
  SELECT 'P|m|'||w.name||'|'||p.oid::regprocedure::text||'|'||has_function_privilege(w.oid,p.oid,'EXECUTE')::int
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    CROSS JOIN who w
   WHERE w.oid<>0 AND p.prokind IN ('f','p')
     AND NOT EXISTS (SELECT 1 FROM ext WHERE ext.classid='pg_proc'::regclass AND ext.objid=p.oid)
  UNION ALL
  SELECT 'L|d|'||pg_get_userbyid(d.defaclrole)||'|'||coalesce((SELECT nspname FROM pg_namespace WHERE oid=d.defaclnamespace),'-')
         ||'|'||d.defaclobjtype::text||'|'||CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END||'|'||a.privilege_type
    FROM pg_default_acl d, aclexplode(d.defaclacl) a)
SELECT y FROM (
  SELECT x AS y, 0 AS o FROM l WHERE NOT :digest
  UNION ALL
  SELECT 'portable '||encode(sha256(convert_to(coalesce(string_agg(x,E'\n' ORDER BY x COLLATE "C") FILTER (WHERE x LIKE 'P|%'),''),'UTF8')),'hex'), 1
    FROM l HAVING :digest
  UNION ALL
  SELECT 'local '||encode(sha256(convert_to(coalesce(string_agg(x,E'\n' ORDER BY x COLLATE "C") FILTER (WHERE x LIKE 'L|%'),''),'UTF8')),'hex'), 2
    FROM l HAVING :digest) s
ORDER BY o, y COLLATE "C";
COMMIT;
