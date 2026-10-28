-- Fingeraftryk af review-trin-b-blokken (db-migrations.sql, `-- BEGIN review-trin-b` .. `-- END review-trin-b`): sha256
-- over de fire funktioners definition og om anon/authenticated/service_role må kalde dem (ikke rå proacl, som bærer
-- ejerens rollenavn). Funktionerne findes før og efter blokken (CREATE OR REPLACE): n=4 begge gange. Læsetransaktion.
SELECT 'TRINB sha='||encode(sha256(convert_to(string_agg(l, E'\n' ORDER BY l COLLATE "C"), 'UTF8')), 'hex')||' n='||count(*)
  FROM (SELECT p.oid::regprocedure::text||E'\t'||pg_get_functiondef(p.oid)
               ||E'\tanon='||has_function_privilege('anon',p.oid,'EXECUTE')||E'\tauthenticated='||has_function_privilege('authenticated',p.oid,'EXECUTE')
               ||E'\tservice_role='||has_function_privilege('service_role',p.oid,'EXECUTE') l
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE (n.nspname,p.proname) IN (('private','preview_relation_promotions'),('public','red_edit_oplysning'),
                 ('public','red_slet_oplysning'),('public','regen_person_visning'))) x;
