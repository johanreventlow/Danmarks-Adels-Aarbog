-- Fingeraftryk af placement-blokkens DDL (#150 trin 5c-1, db-migrations.sql): sha256 over definitionen af blokkens
-- funktioner og om anon/authenticated må kalde dem (ikke rå proacl, som bærer ejerens rollenavn), plus linjer for
-- ledger-tabellen, dens view, de fire vokabularkoder og slaegt-versioneringen. Kan køre før blokken (funktionerne
-- mangler: lavere n og `findes=false`). Læsetransaktion.
SELECT 'DDL150 sha='||encode(sha256(convert_to(string_agg(l, E'\n' ORDER BY l COLLATE "C"), 'UTF8')), 'hex')||' n='||count(*) FILTER (WHERE fn)
  FROM (SELECT true fn, p.oid::regprocedure::text||E'\t'||pg_get_functiondef(p.oid)
               ||E'\tanon='||has_function_privilege('anon',p.oid,'EXECUTE')||E'\tauthenticated='||has_function_privilege('authenticated',p.oid,'EXECUTE') l
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE (n.nspname,p.proname) IN (('private','validate_source_record_placement'),('private','placement_header_violations'),
                 ('private','legacy_external_id_sha256'),('private','header_observation_uuid'),('private','write_header_evidence'),
                 ('private','write_record_placement'),('private','write_persona_placement'),('private','record_legacy_disposition'),
                 ('private','lineage_of_entry'),('private','membership_state'),('private','membership_is_current'),
                 ('private','placement_membership_not_current'),('private','placement_membership_set'),
                 ('public','red_preview_placement_memberships'),('public','red_promote_placement_memberships'),
                 ('public','red_reverse_placement_membership'))
        UNION ALL
        SELECT false, rel||' findes='||(c.oid IS NOT NULL)||' rls='||coalesce(c.relrowsecurity::text,'-')
               ||' triggere='||coalesce((SELECT string_agg(t.tgname, ',' ORDER BY t.tgname) FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal),'-')
               ||' anon='||coalesce(has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE')::text,'-')
               ||' authenticated='||coalesce(has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE')::text,'-')
               ||' service_role='||coalesce(has_table_privilege('service_role',c.oid,'SELECT,INSERT,UPDATE,DELETE')::text,'-')
          FROM (VALUES ('private.legacy_placement_disposition'),('private.legacy_placement_disposition_current')) v(rel)
          LEFT JOIN pg_class c ON c.oid=to_regclass(v.rel)::oid
        UNION ALL
        SELECT false, 'vocab header='||(SELECT string_agg(code, ',' ORDER BY code) FROM private.vocab
                                         WHERE scheme='observation_kind' AND code LIKE 'header\_%')
        UNION ALL
        SELECT false, 'slaegt registry='||EXISTS (SELECT 1 FROM public.version_pk_registry WHERE tabel='slaegt')
               ||' trigger='||EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.slaegt'::regclass AND tgname='trg_log_slaegt')) x;
