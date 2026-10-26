-- Fingeraftryk af dubletreglens 4 funktioner (#151-blokken i db-migrations.sql): sha256 over definitionen og om anon/
-- authenticated må kalde dem (ikke rå proacl, der bærer ejerens rollenavn og derfor er forskellig fra base til base).
-- Bruges før og efter, at blokken lægges i prod (#240-sessionen, decisions 2026-10-26). Læsetransaktion.
SELECT 'DDL151 sha='||encode(sha256(convert_to(string_agg(p.oid::regprocedure::text||E'\t'||pg_get_functiondef(p.oid)
         ||E'\tanon='||has_function_privilege('anon',p.oid,'EXECUTE')||E'\tauthenticated='||has_function_privilege('authenticated',p.oid,'EXECUTE'),
         E'\n' ORDER BY p.oid::regprocedure::text), 'UTF8')), 'hex')||' n='||count(*)
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE (n.nspname,p.proname) IN (('public','red_afgoer_source_persona'),('private','control_run_status'),
                                 ('private','relation_binding_state'),('public','red_source_persona_queue'));
