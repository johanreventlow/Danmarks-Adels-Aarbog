-- Fingeraftryk af rute A's DDL (#248, genåbnings-blokken i db-migrations.sql): sha256 over definitionen af de 3
-- funktioner og om anon/authenticated må kalde dem (ikke rå proacl, som bærer ejerens rollenavn), plus én linje for
-- tabellen private.relation_reopen: findes, RLS, de to triggere og om anon/authenticated/service_role har adgang.
-- Kan køre før blokken (RPC'en og tabellen mangler: n=2 og tabellinjen `findes=false`). Læsetransaktion.
SELECT 'DDL248A sha='||encode(sha256(convert_to(string_agg(l, E'\n' ORDER BY l COLLATE "C"), 'UTF8')), 'hex')||' n='||count(*) FILTER (WHERE fn)
  FROM (SELECT true fn, p.oid::regprocedure::text||E'\t'||pg_get_functiondef(p.oid)
               ||E'\tanon='||has_function_privilege('anon',p.oid,'EXECUTE')||E'\tauthenticated='||has_function_privilege('authenticated',p.oid,'EXECUTE') l
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE (n.nspname,p.proname) IN (('private','relation_binding_state'),('private','spouse_exception_projection'),
                                         ('public','red_genaabn_relation_interpretation'))
        UNION ALL
        SELECT false, 'private.relation_reopen findes='||(c.oid IS NOT NULL)||' rls='||coalesce(c.relrowsecurity::text,'-')
               ||' triggere='||coalesce((SELECT string_agg(t.tgname, ',' ORDER BY t.tgname) FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal),'-')
               ||' anon='||coalesce(has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE')::text,'-')
               ||' authenticated='||coalesce(has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE')::text,'-')
               ||' service_role='||coalesce(has_table_privilege('service_role',c.oid,'SELECT,INSERT,UPDATE,DELETE')::text,'-')
          FROM (SELECT to_regclass('private.relation_reopen')::oid oid) r LEFT JOIN pg_class c ON c.oid=r.oid) x;
