-- Indholds-id (#151, spec 2026-10-21-trin5ab-indholds-id-design.md §5.4): de ændrede funktioner skal være ens i en
-- frisk base (schema.sql) og en migreret base (db-migrations.sql). Én linje pr. funktion; antallet tjekkes af kalderen,
-- så en manglende funktion ikke giver en tom og dermed falsk ens diff.
\set ON_ERROR_STOP on
SELECT l FROM (
  SELECT p.oid::regprocedure::text||'|'||p.prosecdef||'|'||coalesce(array_to_string(p.proconfig,','),'')||'|'||
         (SELECT string_agg(r||'='||has_function_privilege(r,p.oid,'EXECUTE'),',' ORDER BY r)
            FROM unnest(ARRAY['anon','authenticated','service_role']) r)||'|'||
         encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex') AS l
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE (n.nspname,p.proname) IN (('private','content_uuid'),('private','decide_source_persona_identity'),
     ('private','identity_candidate_input'),('public','red_record_identity_candidates'),('private','write_relation_persona'),
     ('private','persona_family_context'),('public','red_register_identity_control_run'),
     ('private','spouse_exception_projection'),('private','relation_persona_v3_input'))) x
 ORDER BY l COLLATE "C";
