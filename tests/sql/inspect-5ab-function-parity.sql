-- Indholds-id (#151, spec 2026-10-21-trin5ab-indholds-id-design.md §5.4): de ændrede funktioner skal være ens i en
-- frisk base (schema.sql) og en migreret base (db-migrations.sql). Én linje pr. funktion; antallet tjekkes af kalderen,
-- så en manglende funktion ikke giver en tom og dermed falsk ens diff.
-- Review-handling A3 (fund 1b-01/1b-02, B9): også de 17 RED-8-funktioner (id-tildeling via DEFAULT i stedet for
-- max(id)+1), så schema.sql ikke igen kan halte efter migrationerne her.
-- Review-handling trin B (blokken review-trin-b): også preview_relation_promotions, red_slet_oplysning og
-- regen_person_visning (red_edit_oplysning er allerede med under RED-8). 5c-2/B11 (blokken 5c2-b11): de offentlige
-- læse-RPC'er og bindingshjælperen. Trin 6c-2a (vej B): værdisammenligningen binding_value_matches.
-- I alt 13 + 17 + 3 + 3 + 1 = 37 linjer.
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
     ('private','spouse_exception_projection'),('private','relation_persona_v3_input'),
     ('public','red_afgoer_source_persona'),('private','control_run_status'),
     ('private','relation_binding_state'),('public','red_source_persona_queue'),
     -- RED-8 (A3)
     ('public','red_opret_person'),('public','red_opret_kilde'),('public','red_opret_estate'),
     ('public','red_opret_organisation'),('public','red_opret_media'),('public','red_registrer_media_variant'),
     ('public','red_opret_story'),('public','red_set_story_kilder'),('public','red_set_feed_pin'),
     ('public','begin_change_set'),('public','log_change'),('public','_ensure_foraeldrefamilie_redaktionel'),
     ('public','red_opret_fakta'),('public','red_upsert_fakta'),('public','red_tilfoej_oplysning'),
     ('public','red_edit_oplysning'),('public','red_tilfoej_foraeldre_paastand'),
     -- review-trin-b
     ('private','preview_relation_promotions'),('public','red_slet_oplysning'),('public','regen_person_visning'),
     -- 5c2-b11
     ('private','assertion_binding_current'),('public','public_person_facts'),
     ('public','public_person_source_coordinates'),
     -- 6c-2a
     ('private','binding_value_matches'))) x
 ORDER BY l COLLATE "C";
