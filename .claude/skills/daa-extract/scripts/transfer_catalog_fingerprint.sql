-- Katalog-fingeraftryk (5a+5b-overførslen, plan A Task 1). Læse-kun; ingen data, ingen oid'er, ejere eller ACL'er.
-- Linjer: <del>|<art>|<identitet>|<md5>|<ejet>, sorteret COLLATE "C".
--   del P (portabel, prod ↔ lokal restore): objekter i public/private, der ikke er ejet af en extension.
--     r tabel (relkind r/p: persistence, RLS, force-RLS, reloptions) · v view · m matview (definition + reloptions)
--     c kolonne · k constraint · i indeks · f funktion/procedure · t trigger · p policy
--     s sekvens (ejet=1 når en kolonne ejer den: serial/identity) · y enum/sammensat type · o domæne
--   c/k/i/t/p har identiteten schema.tabel.navn, så fortrydelsen kan se, om relationen er ny.
--   del L (prod-lokal, kun prod mod prod over tid): n pr. andet skema (antal relationer|antal funktioner|md5 af navne)
--     og p for politikker på storage.objects.
-- Med -v mode=digest: to linjer, »portable <sha256>« og »local <sha256>« (sha over delens linjer forbundet med \n).
\set ON_ERROR_STOP on
\if :{?mode}
\set digest true
\else
\set digest false
\endif
BEGIN READ ONLY;
SET LOCAL search_path TO pg_catalog;
SET LOCAL TimeZone='UTC';
SET LOCAL DateStyle='ISO, MDY';
SET LOCAL IntervalStyle='postgres';
SET LOCAL extra_float_digits=1;
SET LOCAL row_security=off;
WITH ns AS (SELECT oid, nspname FROM pg_namespace WHERE nspname IN ('public','private')),
ext AS (SELECT classid, objid FROM pg_depend WHERE deptype='e'),
rel AS (
  SELECT c.oid, c.relname, c.relkind, c.relpersistence, c.relrowsecurity, c.relforcerowsecurity, c.reloptions, ns.nspname
    FROM pg_class c JOIN ns ON ns.oid=c.relnamespace
   WHERE NOT EXISTS (SELECT 1 FROM ext WHERE ext.classid='pg_class'::regclass AND ext.objid=c.oid)),
l AS (
  SELECT 'P|r|'||nspname||'.'||relname||'|'||md5(concat_ws(';',relkind,relpersistence,relrowsecurity,relforcerowsecurity,
         coalesce(array_to_string(reloptions,','),'')))||'|0' AS x
    FROM rel WHERE relkind IN ('r','p')
  UNION ALL
  SELECT 'P|'||CASE relkind WHEN 'm' THEN 'm' ELSE 'v' END||'|'||nspname||'.'||relname||'|'||md5(concat_ws(';',relkind,pg_get_viewdef(oid),coalesce(array_to_string(reloptions,','),'')))||'|0'
    FROM rel WHERE relkind IN ('v','m')
  UNION ALL
  SELECT 'P|c|'||r.nspname||'.'||r.relname||'.'||a.attname||'|'||md5(concat_ws(';',format_type(a.atttypid,a.atttypmod),a.attnotnull,
         a.attidentity,a.attgenerated,coalesce(pg_get_expr(d.adbin,d.adrelid),'')))||'|0'
    FROM rel r JOIN pg_attribute a ON a.attrelid=r.oid AND a.attnum>0 AND NOT a.attisdropped
    LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
   WHERE r.relkind IN ('r','p')
  UNION ALL
  SELECT 'P|k|'||r.nspname||'.'||r.relname||'.'||k.conname||'|'||md5(concat_ws(';',k.contype,pg_get_constraintdef(k.oid)))||'|0'
    FROM pg_constraint k JOIN rel r ON r.oid=k.conrelid
  UNION ALL
  SELECT 'P|i|'||r.nspname||'.'||r.relname||'.'||ic.relname||'|'||md5(pg_get_indexdef(i.indexrelid))||'|0'
    FROM pg_index i JOIN rel r ON r.oid=i.indrelid JOIN pg_class ic ON ic.oid=i.indexrelid
  UNION ALL
  SELECT 'P|f|'||p.oid::regprocedure::text||'|'||md5(pg_get_functiondef(p.oid))||'|0'
    FROM pg_proc p JOIN ns ON ns.oid=p.pronamespace
   WHERE p.prokind IN ('f','p')
     AND NOT EXISTS (SELECT 1 FROM ext WHERE ext.classid='pg_proc'::regclass AND ext.objid=p.oid)
  UNION ALL
  SELECT 'P|t|'||r.nspname||'.'||r.relname||'.'||t.tgname||'|'||md5(concat_ws(';',t.tgenabled,pg_get_triggerdef(t.oid)))||'|0'
    FROM pg_trigger t JOIN rel r ON r.oid=t.tgrelid WHERE NOT t.tgisinternal
  UNION ALL
  SELECT CASE WHEN pn.nspname IN ('public','private') THEN 'P' ELSE 'L' END||'|p|'||pn.nspname||'.'||pc.relname||'.'||po.polname||'|'
         ||md5(concat_ws(';',po.polcmd,po.polpermissive,
               (SELECT string_agg(CASE WHEN r=0 THEN 'PUBLIC' ELSE pg_get_userbyid(r) END,',' ORDER BY CASE WHEN r=0 THEN 'PUBLIC' ELSE pg_get_userbyid(r) END COLLATE "C")
                  FROM unnest(po.polroles) r),
               coalesce(pg_get_expr(po.polqual,po.polrelid),''),coalesce(pg_get_expr(po.polwithcheck,po.polrelid),'')))||'|0'
    FROM pg_policy po JOIN pg_class pc ON pc.oid=po.polrelid JOIN pg_namespace pn ON pn.oid=pc.relnamespace
   WHERE pn.nspname IN ('public','private') OR (pn.nspname='storage' AND pc.relname='objects')
  UNION ALL
  SELECT 'P|s|'||r.nspname||'.'||r.relname||'|'||md5(concat_ws(';',s.seqtypid::regtype::text,s.seqincrement,s.seqmin,s.seqmax,s.seqcycle))||'|'
         ||CASE WHEN EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid='pg_class'::regclass AND d.objid=r.oid
                              AND d.refclassid='pg_class'::regclass AND d.deptype IN ('a','i')) THEN '1' ELSE '0' END
    FROM rel r JOIN pg_sequence s ON s.seqrelid=r.oid WHERE r.relkind='S'
  UNION ALL
  SELECT 'P|'||CASE t.typtype WHEN 'd' THEN 'o' ELSE 'y' END||'|'||ns.nspname||'.'||t.typname||'|'||md5(concat_ws(';',t.typtype,
         CASE t.typtype
           WHEN 'e' THEN (SELECT string_agg(e.enumlabel,',' ORDER BY e.enumsortorder) FROM pg_enum e WHERE e.enumtypid=t.oid)
           WHEN 'd' THEN format_type(t.typbasetype,t.typtypmod)||';'||t.typnotnull||';'||coalesce(t.typdefault,'')||';'
                         ||coalesce((SELECT string_agg(pg_get_constraintdef(k.oid),',' ORDER BY k.conname COLLATE "C") FROM pg_constraint k WHERE k.contypid=t.oid),'')
           ELSE (SELECT string_agg(a.attname||' '||format_type(a.atttypid,a.atttypmod),',' ORDER BY a.attnum)
                   FROM pg_attribute a WHERE a.attrelid=t.typrelid AND a.attnum>0 AND NOT a.attisdropped) END))||'|0'
    FROM pg_type t JOIN ns ON ns.oid=t.typnamespace
   WHERE (t.typtype IN ('e','d') OR (t.typtype='c' AND (SELECT relkind FROM pg_class WHERE oid=t.typrelid)='c'))
     AND NOT EXISTS (SELECT 1 FROM ext WHERE ext.classid='pg_type'::regclass AND ext.objid=t.oid)
  UNION ALL
  SELECT 'L|n|'||o.nspname||'|'||md5(concat_ws(';',
         (SELECT count(*) FROM pg_class c WHERE c.relnamespace=o.oid),
         (SELECT count(*) FROM pg_proc p WHERE p.pronamespace=o.oid),
         coalesce((SELECT string_agg(x,',' ORDER BY x COLLATE "C") FROM (
            SELECT c.relname::text x FROM pg_class c WHERE c.relnamespace=o.oid
            UNION ALL SELECT p.oid::regprocedure::text FROM pg_proc p WHERE p.pronamespace=o.oid) s),'')))||'|0'
    FROM pg_namespace o
   WHERE o.nspname NOT IN ('public','private','information_schema') AND o.nspname NOT LIKE 'pg\_%')
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
