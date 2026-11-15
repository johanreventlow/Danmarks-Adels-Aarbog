-- Indholds-id (#151, spec 2026-10-21-trin5ab-indholds-id-design.md §5.4): de ændrede funktioner skal være ens i en
-- frisk base (schema.sql) og en migreret base (db-migrations.sql). Én linje pr. funktion; antallet tjekkes af kalderen,
-- så en manglende funktion ikke giver en tom og dermed falsk ens diff.
-- Review-handling A3 (fund 1b-01/1b-02, B9): også de 17 RED-8-funktioner (id-tildeling via DEFAULT i stedet for
-- max(id)+1), så schema.sql ikke igen kan halte efter migrationerne her.
-- Review-handling trin B (blokken review-trin-b): også preview_relation_promotions, red_slet_oplysning og
-- regen_person_visning (red_edit_oplysning er allerede med under RED-8). 5c-2/B11 (blokken 5c2-b11): de offentlige
-- læse-RPC'er og bindingshjælperen. Trin 6c-2a (vej B): værdisammenligningen binding_value_matches.
-- Trin 6c-2b (forslagsversion): normaliser_dato_markoer_v1 og red_normaliser_forslag; (påstandsrettelse): saml_blanktegn_v1,
-- navn_forkortes, red_ret_paastand og red_paastand_historik; (én binding pr. påstand): validate_interpretation_promotion_items.
-- Trin 6m-a (forslagsversion med menneskelig læsning): red_ret_forslag, red_decide_interpretation (reserveret grundlag)
-- og kontroller_forslag_binding_v1. Trin 6c-3a (tekstrevision og relationer): verify_relation_persona_receipts,
-- spouse_principal_person og write_text_revision_reconciliation (write_relation_persona, persona_family_context og
-- relation_binding_state står allerede under 5ab).
-- Trin 6d-1 (blokken trin 6d-1): record_legacy_disposition, red_promote_placement_memberships,
-- membership_component_states, placement_header_violations og placement_human_header_levels
-- (public_person_source_coordinates står allerede under 5c2-b11).
-- Trin 6d-3 (blokken trin 6d-3): tekstfoldningen relation_fold_raw_text, relation_text_form,
-- relation_name_compare_text, begge overloads af relation_ordered_windows og relation_marriage_ordinals
-- (write_relation_persona, identity_candidate_input og verify_relation_persona_receipts står allerede ovenfor).
-- Redaktøren ser levende (blokken redaktoer-ser-levende, decisions 2026-11-13): public_family_sources (public_person_facts
-- og public_person_source_coordinates står allerede under 5c2-b11).
-- Kodereview 36 §D1 (bølge 2): narrative_record_state, hvis låseblok var gledet (schema.sql manglede kildefilteret,
-- prod kører migrationsversionen).
-- I alt 13 + 17 + 3 + 3 + 1 + 7 + 3 + 3 + 5 + 6 + 1 + 1 + 1 = 64 linjer (dato-markoer-v2: normaliser_dato_markoer_v2).
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
     ('private','binding_value_matches'),
     -- 6c-2b
     ('private','normaliser_dato_markoer_v1'),('private','normaliser_dato_markoer_v2'),('public','red_normaliser_forslag'),
     ('private','saml_blanktegn_v1'),('private','navn_forkortes'),('public','red_ret_paastand'),
     ('public','red_paastand_historik'),('private','validate_interpretation_promotion_items'),
     -- 6m-a
     ('public','red_ret_forslag'),('public','red_decide_interpretation'),('private','kontroller_forslag_binding_v1'),
     -- 6c-3a
     ('private','verify_relation_persona_receipts'),('private','spouse_principal_person'),
     ('private','write_text_revision_reconciliation'),
     -- 6d-1
     ('private','record_legacy_disposition'),('public','red_promote_placement_memberships'),
     ('private','membership_component_states'),('private','placement_header_violations'),
     ('private','placement_human_header_levels'),
     -- 6d-3
     ('private','relation_fold_raw_text'),('private','relation_text_form'),('private','relation_name_compare_text'),
     ('private','relation_ordered_windows'),('private','relation_marriage_ordinals'),
     -- redaktoer-ser-levende
     ('public','public_family_sources'),
     -- kodereview 36 §D1
     ('private','narrative_record_state'))) x
 ORDER BY l COLLATE "C";
