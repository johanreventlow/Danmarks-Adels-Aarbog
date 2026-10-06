-- =============================================================
-- db-verify.sql
-- Verifikations-script til Supabase SQL Editor.
--
-- Kør dette script MOD EN BRANCH ELLER KOPI af databasen,
-- EFTER at følgende filer er kørt i Supabase SQL Editor:
--   1. db-migrations.sql  (idempotent afstemning af skema)
--   2. db-rls.sql         (RLS-politikker + grants)
--
-- Advarsel: Nogle assert-blokke seeder midlertidige testrækker
-- (fx subjekt_id=-99 eller temporære fact/assertion/conclusion-
-- rækker) og rydder selv op bagefter. Kør ikke mod prod-base.
--
-- NOTE OM ROLLE-GATING: Supabase SQL Editor kører som databaseejer
-- (postgres/service_role), IKKE som en authenticated Supabase-bruger.
-- Det betyder auth.uid() returnerer NULL → current_rolle() returnerer
-- 'medlem'. Asserts der forventer AFVISNING (Kun redaktion-RAISE)
-- fungerer som forventet i SQL Editor.
-- Asserts der kræver happy-path FOR redaktion (fx Task 4's
-- slet-re-peg) kræver enten:
--   (a) Kørsel som funktionsejer (SET ROLE til ejer, derefter RESET ROLE),
--   (b) Midlertidigt seedet redaktion-profil for auth.uid(), eller
--   (c) Test via app-laget mod en redaktion-session (Task 9 i planen).
-- Dette er dokumenteret pr. assert-blok nedenfor.
-- =============================================================

-- Supabase installs extension functions in `extensions`; plain PostgreSQL may
-- install them in `public`.  Keep both legitimate layouts callable while the
-- five two-connection gates below fail closed if dblink is not installed.
SET search_path TO public, private, extensions, pg_catalog;


-- ===== #152 Task 1: narrative publication event foundation =====
DO $narrative_record_foundation_verify$
DECLARE
  v_role text;
  v_table text;
  v_privilege text;
  v_default text;
  v_source bigint;
  v_person bigint;
  v_narrative bigint;
  v_change_set bigint;
  v_run uuid := gen_random_uuid();
  v_record uuid := gen_random_uuid();
  v_binding uuid := gen_random_uuid();
  v_event uuid := gen_random_uuid();
  v_public_ref uuid;
  v_error text;
BEGIN
  IF to_regprocedure('public.narrative_record_contract_version()') IS NULL
     OR to_regclass('private.narrative_publication_event') IS NULL
     OR to_regclass('private.narrative_legacy_publication') IS NULL THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_FOUNDATION_MISSING';
  END IF;
  IF public.narrative_record_contract_version() NOT IN (1,2) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_CONTRACT_VERSION_INVALID';
  END IF;

  SELECT pg_get_expr(d.adbin,d.adrelid)
    INTO v_default
    FROM pg_attribute a
    JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
   WHERE a.attrelid='private.source_record'::regclass
     AND a.attname='public_ref';
  IF replace(v_default,'pg_catalog.','') IS DISTINCT FROM 'gen_random_uuid()'
     OR EXISTS (SELECT 1 FROM private.source_record WHERE public_ref IS NULL)
     OR (SELECT count(*) FROM private.source_record)
        IS DISTINCT FROM (SELECT count(DISTINCT public_ref) FROM private.source_record) THEN
    RAISE EXCEPTION 'SOURCE_RECORD_PUBLIC_REF_INTEGRITY_INVALID';
  END IF;

  IF EXISTS (
    SELECT 1 FROM private.narrative_publication_event event
     WHERE event.before_state_sha256 !~ '^[0-9a-f]{64}$'
        OR event.after_state_sha256 !~ '^[0-9a-f]{64}$'
        OR jsonb_typeof(event.before_state)<>'object'
        OR jsonb_typeof(event.after_state)<>'object'
        OR btrim(event.decision_basis)=''
        OR btrim(event.decided_by_name)=''
        OR event.stream_ref<>coalesce(event.binding_id,event.legacy_publication_ref)
        OR NOT (
          (event.binding_id IS NOT NULL AND event.source_record_id IS NOT NULL
           AND event.legacy_publication_ref IS NULL)
          OR
          (event.binding_id IS NULL AND event.source_record_id IS NULL
           AND event.legacy_publication_ref IS NOT NULL)
        )
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_SHAPE_INVALID';
  END IF;
  IF EXISTS (
    SELECT 1
      FROM private.narrative_publication_event event
      LEFT JOIN private.narrative_publication_event reversed
        ON reversed.id=event.reversed_event_id
     WHERE (event.event_type='reversal') IS DISTINCT FROM
           (event.reversed_event_id IS NOT NULL)
        OR (
          event.reversed_event_id IS NOT NULL
          AND (
            reversed.id IS NULL
            OR reversed.stream_ref<>event.stream_ref
            OR reversed.stream_version>=event.stream_version
          )
        )
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_REVERSAL_INVALID';
  END IF;
  IF EXISTS (
    SELECT 1
      FROM private.narrative_publication_event event
      LEFT JOIN private.narrative_record_publication binding
        ON binding.id=event.binding_id
      LEFT JOIN private.narrative_legacy_publication legacy
        ON legacy.legacy_publication_ref=event.legacy_publication_ref
     WHERE (
       event.binding_id IS NOT NULL
       AND (
         binding.id IS NULL
         OR binding.narrative_id<>event.narrative_id
         OR binding.source_record_id<>event.source_record_id
       )
     ) OR (
       event.legacy_publication_ref IS NOT NULL
       AND (
         legacy.legacy_publication_ref IS NULL
         OR legacy.narrative_id<>event.narrative_id
         OR legacy.source_id<>event.source_id
       )
     )
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_IDENTITY_INVALID';
  END IF;
  IF EXISTS (
    SELECT 1 FROM private.narrative_legacy_publication legacy
     WHERE legacy.baseline_sha256 !~ '^[0-9a-f]{64}$'
        OR jsonb_typeof(legacy.baseline_state)<>'object'
        OR (
          legacy.latest_event_id IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM private.narrative_publication_event event
             WHERE event.id=legacy.latest_event_id
               AND event.legacy_publication_ref=legacy.legacy_publication_ref
               AND event.narrative_id=legacy.narrative_id
               AND event.source_id=legacy.source_id
               AND NOT EXISTS (
                 SELECT 1 FROM private.narrative_publication_event later
                  WHERE later.stream_ref=event.stream_ref
                    AND later.stream_version>event.stream_version
               )
          )
        )
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_INTEGRITY_INVALID';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
     WHERE tgrelid='private.source_record'::regclass
       AND tgname='trg_source_record_append_only'
       AND tgenabled<>'D'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger
     WHERE tgrelid='private.narrative_publication_event'::regclass
       AND tgname='trg_narrative_publication_event_append_only'
       AND tgenabled<>'D'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger
     WHERE tgrelid='private.narrative_publication_event'::regclass
       AND tgname='trg_narrative_publication_event_validate'
       AND tgenabled<>'D'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger
     WHERE tgrelid='private.narrative_legacy_publication'::regclass
       AND tgname='trg_narrative_legacy_publication_validate'
       AND tgenabled<>'D'
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_IMMUTABILITY_TRIGGER_MISSING';
  END IF;

  FOREACH v_table IN ARRAY ARRAY[
    'private.narrative_publication_event',
    'private.narrative_legacy_publication'
  ] LOOP
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=v_table::regclass) THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PRIVATE_RLS_DISABLED: %',v_table;
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      FOREACH v_privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE'] LOOP
        IF has_table_privilege(v_role,v_table,v_privilege) THEN
          RAISE EXCEPTION 'NARRATIVE_RECORD_PRIVATE_GRANT_INVALID: % % %',
            v_role,v_privilege,v_table;
        END IF;
      END LOOP;
    END LOOP;
    IF EXISTS (
      SELECT 1
        FROM pg_class relation
        CROSS JOIN LATERAL aclexplode(
          coalesce(relation.relacl,acldefault('r',relation.relowner))
        ) acl
       WHERE relation.oid=v_table::regclass
         AND acl.grantee=0
         AND acl.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')
    ) THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PRIVATE_PUBLIC_GRANT_INVALID: %',v_table;
    END IF;
  END LOOP;
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_function_privilege(
      v_role,'private.validate_narrative_publication_event()'::regprocedure,'EXECUTE'
    ) OR has_function_privilege(
      v_role,'private.reject_narrative_publication_event_mutation()'::regprocedure,'EXECUTE'
    ) OR has_function_privilege(
      v_role,'private.validate_narrative_legacy_publication()'::regprocedure,'EXECUTE'
    ) THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PRIVATE_HELPER_GRANT_INVALID: %',v_role;
    END IF;
  END LOOP;
  IF EXISTS (
    SELECT 1
      FROM pg_proc function
      CROSS JOIN LATERAL aclexplode(
        coalesce(function.proacl,acldefault('f',function.proowner))
      ) acl
     WHERE function.oid IN (
       'private.validate_narrative_publication_event()'::regprocedure,
       'private.reject_narrative_publication_event_mutation()'::regprocedure,
       'private.validate_narrative_legacy_publication()'::regprocedure
     )
       AND acl.grantee=0
       AND acl.privilege_type='EXECUTE'
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_PRIVATE_HELPER_PUBLIC_GRANT_INVALID';
  END IF;
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF NOT has_function_privilege(
      v_role,'public.narrative_record_contract_version()'::regprocedure,'EXECUTE'
    ) THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_VERSION_GRANT_MISSING: %',v_role;
    END IF;
  END LOOP;
  IF EXISTS (
    SELECT 1
      FROM pg_proc function
      CROSS JOIN LATERAL aclexplode(
        coalesce(function.proacl,acldefault('f',function.proowner))
      ) acl
     WHERE function.oid='public.narrative_record_contract_version()'::regprocedure
       AND acl.grantee=0
       AND acl.privilege_type='EXECUTE'
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_VERSION_PUBLIC_GRANT_INVALID';
  END IF;
  IF EXISTS (
    SELECT 1
      FROM pg_proc function
      JOIN pg_namespace namespace ON namespace.oid=function.pronamespace
     WHERE namespace.nspname='public'
       AND function.prosrc LIKE '%legacy_migrated%'
       -- #166 149b: publiceringshistorikken NAVNGIVER eventtypen for at kunne
       -- markere spec §8's tredje fortryd-trin som reversibelt i redaktørfladen.
       -- Den er ren læsning uden skrivevej, og er derfor den eneste bevidste
       -- undtagelse; enhver anden ny public-funktion, der nævner legacy_migrated
       -- og er kaldbar for en klientrolle, skal fortsat fejle her.
       AND function.oid<>'public.red_person_narrative_publication_history(bigint)'::regprocedure
       AND (
         has_function_privilege('anon',function.oid,'EXECUTE')
         OR has_function_privilege('authenticated',function.oid,'EXECUTE')
         OR has_function_privilege('service_role',function.oid,'EXECUTE')
       )
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_MIGRATION_WRITER_EXPOSED';
  END IF;

  -- Exercise the immutable triggers with a fully rolled-back fixture.
  BEGIN
    SELECT least(coalesce(min(id),0),0)-152 INTO v_source FROM public.source;
    SELECT least(coalesce(min(id),0),0)-152 INTO v_person FROM public.person;
    SELECT least(coalesce(min(id),0),0)-152 INTO v_narrative FROM public.narrative;
    SELECT least(coalesce(min(id),0),0)-152 INTO v_change_set FROM public.change_set;

    INSERT INTO public.source(id,slags,titel)
    VALUES (v_source,'DAA-udgave','Narrative record verify fixture');
    INSERT INTO private.extraction_run(
      id,source_id,run_key,schema_version,extractor_version,profile_version,
      input_sha256,manifest
    ) VALUES (
      v_run,v_source,'narrative-record-verify','1','verify','verify',repeat('1',64),'{}'
    );
    INSERT INTO private.source_record(
      id,source_id,record_key,record_kind,created_run_id
    ) VALUES (
      v_record,v_source,'narrative-record-verify','person',v_run
    ) RETURNING public_ref INTO v_public_ref;

    v_error:=NULL;
    BEGIN
      UPDATE private.source_record SET public_ref=gen_random_uuid() WHERE id=v_record;
    EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
    END;
    IF v_error IS NULL
       OR (SELECT public_ref FROM private.source_record WHERE id=v_record)
          IS DISTINCT FROM v_public_ref THEN
      RAISE EXCEPTION 'SOURCE_RECORD_PUBLIC_REF_IMMUTABILITY_NOT_ENFORCED';
    END IF;

    INSERT INTO public.person(id,levende,privat,visning_navn)
    VALUES (v_person,false,false,'Narrative record verify fixture');
    INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst,privat)
    VALUES (v_narrative,'person',v_person,v_source,'Verify text',false);
    INSERT INTO private.narrative_record_publication(
      id,narrative_id,source_record_id,record_label,citation_label,status
    ) VALUES (v_binding,v_narrative,v_record,'Verify','Verify citation','draft');
    INSERT INTO public.change_set(id,operation,summary)
    VALUES (v_change_set,'narrative_record_verify','Narrative record verify');
    INSERT INTO private.narrative_publication_event(
      id,change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,
      source_id,source_record_id,decision_basis,before_state,after_state,
      before_state_sha256,after_state_sha256,decided_by_name
    ) VALUES (
      v_event,v_change_set,v_binding,1,'baseline',v_binding,v_narrative,v_source,
      v_record,'Verify baseline',jsonb_build_object('state','before'),
      jsonb_build_object('state','after'),repeat('a',64),repeat('b',64),'Verify actor'
    );

    v_error:=NULL;
    BEGIN
      UPDATE private.narrative_publication_event
         SET decision_basis='changed'
       WHERE id=v_event;
    EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
    END;
    IF v_error IS DISTINCT FROM 'NARRATIVE_PUBLICATION_EVENT_APPEND_ONLY' THEN
      RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_UPDATE_NOT_IMMUTABLE';
    END IF;
    v_error:=NULL;
    BEGIN
      DELETE FROM private.narrative_publication_event WHERE id=v_event;
    EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
    END;
    IF v_error IS DISTINCT FROM 'NARRATIVE_PUBLICATION_EVENT_APPEND_ONLY' THEN
      RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_DELETE_NOT_IMMUTABLE';
    END IF;

    RAISE EXCEPTION 'ROLLBACK_NARRATIVE_RECORD_FOUNDATION_VERIFY';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_NARRATIVE_RECORD_FOUNDATION_VERIFY' THEN
      RAISE;
    END IF;
  END;

  RAISE NOTICE 'OK: #152 narrative publication event foundation er additiv, privat og uforanderlig';
END
$narrative_record_foundation_verify$;


-- ===== #152 Task 2: canonical state and typed editor reads =====
DO $narrative_record_state_verify$
DECLARE
  v_role text;
  v_function text;
  v_actual_result text;
  v_state_definition text;
  v_record_lock_position integer;
  v_change_set_lock_position integer;
  v_person_lock_position integer;
  v_projection_position integer;
BEGIN
  IF to_regprocedure('private.narrative_record_labels(uuid)') IS NULL
     OR to_regprocedure('private.narrative_publication_state(bigint,bigint,text)') IS NULL
     OR to_regprocedure('private.narrative_record_state(bigint,bigint,text,boolean)') IS NULL
     OR to_regprocedure('private.narrative_legacy_publication_state(uuid)') IS NULL
     OR to_regprocedure('private.narrative_legacy_state(uuid,boolean)') IS NULL
     OR to_regprocedure('public.red_person_narrative_records(bigint)') IS NULL
     OR to_regprocedure('public.red_person_narrative_publication_history(bigint)') IS NULL
     OR to_regclass('private.narrative_record_publication_record_state_idx') IS NULL
     OR to_regclass('private.source_record_anchor_event_record_state_idx') IS NULL
     OR to_regclass('private.source_record_placement_record_state_idx') IS NULL
     OR to_regclass('private.source_persona_placement_record_state_idx') IS NULL
     OR to_regclass('private.source_persona_identity_person_state_idx') IS NULL
     OR to_regclass('private.source_record_revision_event_successor_state_idx') IS NULL THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_STATE_CONTRACT_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc function
     WHERE function.oid IN (
       'private.narrative_record_labels(uuid)'::regprocedure,
       'private.narrative_publication_state(bigint,bigint,text)'::regprocedure,
       'private.narrative_legacy_publication_state(uuid)'::regprocedure
     )
       AND function.provolatile<>'s'
  ) OR EXISTS (
    SELECT 1 FROM pg_proc function
     WHERE function.oid IN (
       'private.narrative_record_state(bigint,bigint,text,boolean)'::regprocedure,
       'private.narrative_legacy_state(uuid,boolean)'::regprocedure
     )
       AND function.provolatile<>'v'
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_STATE_VOLATILITY_INVALID';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc function
     WHERE function.oid IN (
       'public.red_person_narrative_records(bigint)'::regprocedure,
       'public.red_person_narrative_publication_history(bigint)'::regprocedure
     )
       AND (
         NOT function.prosecdef
         OR function.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[]
       )
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_EDITOR_SECURITY_INVALID';
  END IF;

  SELECT pg_get_function_result(
    'public.red_person_narrative_records(bigint)'::regprocedure
  ) INTO v_actual_result;
  IF v_actual_result IS DISTINCT FROM
       'TABLE(person_id bigint, source_id bigint, source_year integer, source_label text, provenance_kind text, record_key text, source_record_ref uuid, legacy_publication_ref uuid, record_order integer, record_label text, citation_label text, narrative_id bigint, narrative_text text, narrative_private boolean, narrative_side text, publication_status text, text_editable boolean, allowed_actions jsonb, withdrawn_history jsonb, latest_event_version integer, published_text_sha256 text, eligibility_status text, blocking_reason text, state_sha256 text)' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_EDITOR_RESULT_INVALID: %',v_actual_result;
  END IF;
  SELECT pg_get_function_result(
    'public.red_person_narrative_publication_history(bigint)'::regprocedure
  ) INTO v_actual_result;
  IF v_actual_result IS DISTINCT FROM
       'TABLE(event_id uuid, change_set_id bigint, stream_version integer, event_type text, source_record_ref uuid, legacy_publication_ref uuid, before_state_sha256 text, after_state_sha256 text, before_text text, after_text text, decided_by_name text, created_at timestamp with time zone, can_reverse boolean, blocking_reason text)' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_HISTORY_RESULT_INVALID: %',v_actual_result;
  END IF;

  FOREACH v_role IN ARRAY ARRAY['anon','service_role'] LOOP
    IF has_function_privilege(
      v_role,'public.red_person_narrative_records(bigint)','EXECUTE'
    ) OR has_function_privilege(
      v_role,'public.red_person_narrative_publication_history(bigint)','EXECUTE'
    ) THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_EDITOR_PUBLIC_ACL_INVALID: %',v_role;
    END IF;
  END LOOP;
  IF NOT has_function_privilege(
    'authenticated','public.red_person_narrative_records(bigint)','EXECUTE'
  ) OR NOT has_function_privilege(
    'authenticated','public.red_person_narrative_publication_history(bigint)','EXECUTE'
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_EDITOR_AUTHENTICATED_GRANT_MISSING';
  END IF;

  FOREACH v_function IN ARRAY ARRAY[
    'private.narrative_record_labels(uuid)',
    'private.narrative_publication_state(bigint,bigint,text)',
    'private.narrative_record_state(bigint,bigint,text,boolean)',
    'private.narrative_legacy_publication_state(uuid)',
    'private.narrative_legacy_state(uuid,boolean)'
  ] LOOP
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      IF has_function_privilege(v_role,v_function,'EXECUTE') THEN
        RAISE EXCEPTION 'NARRATIVE_RECORD_STATE_PRIVATE_ACL_INVALID: % %',
          v_role,v_function;
      END IF;
    END LOOP;
  END LOOP;

  IF strpos(
       pg_get_functiondef(
         'private.narrative_record_state(bigint,bigint,text,boolean)'::regprocedure
       ),'FOR UPDATE'
     )=0 OR strpos(
       pg_get_functiondef(
         'private.narrative_legacy_state(uuid,boolean)'::regprocedure
       ),'FOR UPDATE'
  )=0 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_STATE_LOCK_MODE_MISSING';
  END IF;

  v_state_definition:=pg_get_functiondef(
    'private.narrative_record_state(bigint,bigint,text,boolean)'::regprocedure
  );
  v_record_lock_position:=strpos(
    v_state_definition,'WHERE record.id=v_record_id FOR UPDATE;'
  );
  v_change_set_lock_position:=strpos(
    v_state_definition,'LOCK TABLE public.change_set IN ACCESS EXCLUSIVE MODE;'
  );
  v_person_lock_position:=strpos(
    v_state_definition,'WHERE person.id=p_person_id FOR UPDATE;'
  );
  v_projection_position:=strpos(
    v_state_definition,'v_publication_state:=private.narrative_publication_state('
  );
  IF v_record_lock_position=0
     OR v_change_set_lock_position<=v_record_lock_position
     OR v_person_lock_position<=v_change_set_lock_position
     OR v_projection_position<=v_person_lock_position THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_PERSON_POLICY_LOCK_ORDER_INVALID';
  END IF;
  IF strpos(v_state_definition,'v_selected_binding_id:=v_active_binding_id')=0
     OR strpos(v_state_definition,'event.binding_id=v_selected_binding_id')=0
     OR strpos(
          v_state_definition,
          'ORDER BY stream_head.change_set_id DESC,stream_head.created_at DESC'
        )=0
     OR strpos(
          v_state_definition,
          '(v_active_binding_id IS NULL OR event.binding_id=v_active_binding_id)'
        )<>0
     OR strpos(
          v_state_definition,
          'ORDER BY binding.created_at DESC,stream_head.created_at DESC'
        )<>0 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_STREAM_CHRONOLOGY_INVALID';
  END IF;

  RAISE NOTICE 'OK: #152 Task 2 canonical state, typed editor/history og ACL er installeret';
END
$narrative_record_state_verify$;


-- ===== Task 1: Tabeller profiles + suggestion =====
-- Forvent: begge tabeller findes, rolle-CHECK håndhæves.

-- ===== DAA 1939 v50 production-writer contract =====
DO $$
BEGIN
  IF to_regclass('private.reimport_1939_authorization') IS NULL
     OR to_regclass('private.reimport_1939_write_batch') IS NULL
     OR to_regclass('private.reimport_1939_write_event') IS NULL
     OR to_regprocedure('public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamp with time zone)') IS NULL
     OR to_regprocedure('public.red_finalize_1939_v50_reimport(uuid)') IS NULL THEN
    RAISE EXCEPTION 'REIMPORT_1939_WRITER_CONTRACT_MISSING';
  END IF;
  IF has_table_privilege('anon','private.reimport_1939_write_event','SELECT')
     OR has_table_privilege('authenticated','private.reimport_1939_write_event','SELECT') THEN
    RAISE EXCEPTION 'REIMPORT_1939_PRIVATE_GRANT_INVALID';
  END IF;
  RAISE NOTICE 'OK: DAA 1939 v50 production-writer contract er installeret og privat';
END $$;

-- #153 Task 5: generic reimport replay receipt is the only public ledger read.
DO $verify_reimport_batch_result$
DECLARE v_definition text;
BEGIN
  IF to_regprocedure('public.red_reimport_batch_result(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_BATCH_RESULT_RPC_MISSING';
  END IF;
  SELECT pg_get_functiondef('public.red_reimport_batch_result(uuid,uuid)'::regprocedure)
    INTO v_definition;
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid='public.red_reimport_batch_result(uuid,uuid)'::regprocedure)
     OR strpos(coalesce(v_definition,''),'SET search_path TO')=0
     OR strpos(v_definition,'pg_catalog')=0 OR strpos(v_definition,'public')=0 OR strpos(v_definition,'private')=0
     OR strpos(v_definition,'REIMPORT_NARRATIVE_RECORD_CONTRACT_REQUIRED')=0
     OR has_function_privilege('anon','public.red_reimport_batch_result(uuid,uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.red_reimport_batch_result(uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_reimport_batch_result(uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_BATCH_RESULT_ACL_INVALID';
  END IF;
  RAISE NOTICE 'OK: #153 generic reimport replay receipt is contract-gated and authenticated-only';
END
$verify_reimport_batch_result$;

-- #153 Task 6: `_1939` is a closed compatibility namespace.  The generic
-- writer and its public replay receipt deliberately have no edition suffix and
-- are therefore absent from this transition-surface allowlist. `_2018` er en
-- tom allowlist: #149a's udgave bor i én profil-JSON, ikke i katalogen.
CREATE OR REPLACE FUNCTION private.assert_reimport_edition_catalog()
RETURNS void
LANGUAGE plpgsql
SET search_path TO pg_catalog, public, private
AS $assert_reimport_edition_catalog$
DECLARE v_drift jsonb;
BEGIN
  WITH expected(object_kind,object_schema,object_name,parent_identity) AS (
    VALUES
      ('relation:v','private','reimport_1939_authorization',NULL),
      ('relation:v','private','reimport_1939_name_completion_result',NULL),
      ('relation:v','private','reimport_1939_write_batch',NULL),
      ('relation:v','private','reimport_1939_write_event',NULL),
      ('type:b','private','_reimport_1939_authorization',NULL),
      ('type:b','private','_reimport_1939_name_completion_result',NULL),
      ('type:b','private','_reimport_1939_write_batch',NULL),
      ('type:b','private','_reimport_1939_write_event',NULL),
      ('type:c','private','reimport_1939_authorization','private.reimport_1939_authorization'),
      ('type:c','private','reimport_1939_name_completion_result','private.reimport_1939_name_completion_result'),
      ('type:c','private','reimport_1939_write_batch','private.reimport_1939_write_batch'),
      ('type:c','private','reimport_1939_write_event','private.reimport_1939_write_event'),
      ('function:f','private','reimport_1939_canonical_json_sha256(jsonb)',NULL),
      ('function:f','private','require_reimport_1939_editor()',NULL),
      ('function:f','public','red_activate_1939_v50_batch(uuid,uuid)',NULL),
      ('function:f','public','red_apply_1939_v50_canonical_delta(uuid,text,jsonb)',NULL),
      ('function:f','public','red_apply_1939_v50_name_completion(uuid,text,jsonb)',NULL),
      ('function:f','public','red_apply_1939_v50_person_create(uuid,text,jsonb)',NULL),
      ('function:f','public','red_apply_1939_v50_source_evidence(uuid,text,jsonb)',NULL),
      ('function:f','public','red_authorize_1939_v50_cutover(uuid,uuid,timestamp with time zone)',NULL),
      ('function:f','public','red_authorize_1939_v50_name_completion(text,uuid,text,text,jsonb,jsonb)',NULL),
      ('function:f','public','red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamp with time zone)',NULL),
      ('function:f','public','red_authorize_1939_v50_reversal(uuid,uuid,timestamp with time zone)',NULL),
      ('function:f','public','red_begin_1939_v50_name_completion(uuid,text,uuid)',NULL),
      ('function:f','public','red_begin_1939_v50_reimport(uuid,text,text)',NULL),
      ('function:f','public','red_finalize_1939_v50_name_completion(uuid)',NULL),
      ('function:f','public','red_finalize_1939_v50_reimport(uuid)',NULL),
      ('function:f','public','red_lock_1939_v50_name_completion(text)',NULL),
      ('function:f','public','red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb)',NULL),
      ('function:f','public','red_reverse_1939_v50_reimport(uuid,uuid)',NULL)
  ), actual(object_kind,object_schema,object_name,parent_identity) AS (
    SELECT 'relation:' || c.relkind::text, n.nspname, c.relname,
      CASE c.relkind
        WHEN 'i' THEN (
          SELECT format('%I.%I',parent_namespace.nspname,parent_relation.relname)
          FROM pg_index index_row
          JOIN pg_class parent_relation ON parent_relation.oid=index_row.indrelid
          JOIN pg_namespace parent_namespace ON parent_namespace.oid=parent_relation.relnamespace
          WHERE index_row.indexrelid=c.oid
        )
        WHEN 'S' THEN (
          SELECT format('%I.%I.%I',parent_namespace.nspname,parent_relation.relname,parent_attribute.attname)
          FROM pg_depend dependency
          JOIN pg_class parent_relation ON parent_relation.oid=dependency.refobjid
          JOIN pg_namespace parent_namespace ON parent_namespace.oid=parent_relation.relnamespace
          JOIN pg_attribute parent_attribute ON parent_attribute.attrelid=parent_relation.oid
            AND parent_attribute.attnum=dependency.refobjsubid
          WHERE dependency.classid='pg_class'::regclass
            AND dependency.objid=c.oid
            AND dependency.refclassid='pg_class'::regclass
            AND dependency.deptype='a'
          LIMIT 1
        )
      END
    FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','private')
      AND (c.relname LIKE '%\_1939%' ESCAPE E'\\'
           OR c.relname LIKE '%\_2018%' ESCAPE E'\\')

    UNION ALL

    SELECT 'type:' || t.typtype::text, n.nspname, t.typname,
      CASE WHEN t.typrelid<>0 THEN (
        SELECT format('%I.%I',parent_namespace.nspname,parent_relation.relname)
        FROM pg_class parent_relation
        JOIN pg_namespace parent_namespace ON parent_namespace.oid=parent_relation.relnamespace
        WHERE parent_relation.oid=t.typrelid
      ) END
    FROM pg_type t
    JOIN pg_namespace n ON n.oid=t.typnamespace
    WHERE n.nspname IN ('public','private')
      AND (t.typname LIKE '%\_1939%' ESCAPE E'\\'
           OR t.typname LIKE '%\_2018%' ESCAPE E'\\')

    UNION ALL

    SELECT 'function:' || p.prokind::text, n.nspname, p.oid::regprocedure::text,NULL::text
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('public','private')
      AND (p.proname LIKE '%\_1939%' ESCAPE E'\\'
           OR p.proname LIKE '%\_2018%' ESCAPE E'\\')

    UNION ALL

    SELECT 'trigger',n.nspname,t.tgname,format('%I.%I',n.nspname,c.relname)
    FROM pg_trigger t
    JOIN pg_class c ON c.oid=t.tgrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE NOT t.tgisinternal
      AND n.nspname IN ('public','private')
      AND (t.tgname LIKE '%\_1939%' ESCAPE E'\\'
           OR t.tgname LIKE '%\_2018%' ESCAPE E'\\')

    UNION ALL

    SELECT 'constraint:' || constraint_row.contype::text,
      coalesce(relation_namespace.nspname,type_namespace.nspname),constraint_row.conname,
      CASE
        WHEN constraint_row.conrelid<>0 THEN format('%I.%I',relation_namespace.nspname,relation_row.relname)
        ELSE format('%I.%I',type_namespace.nspname,type_row.typname)
      END
    FROM pg_constraint constraint_row
    LEFT JOIN pg_class relation_row ON relation_row.oid=constraint_row.conrelid
    LEFT JOIN pg_namespace relation_namespace ON relation_namespace.oid=relation_row.relnamespace
    LEFT JOIN pg_type type_row ON type_row.oid=constraint_row.contypid
    LEFT JOIN pg_namespace type_namespace ON type_namespace.oid=type_row.typnamespace
    WHERE coalesce(relation_namespace.nspname,type_namespace.nspname) IN ('public','private')
      AND (constraint_row.conname LIKE '%\_1939%' ESCAPE E'\\'
           OR constraint_row.conname LIKE '%\_2018%' ESCAPE E'\\')

    UNION ALL

    SELECT 'policy',n.nspname,p.polname,format('%I.%I',n.nspname,c.relname)
    FROM pg_policy p
    JOIN pg_class c ON c.oid=p.polrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','private')
      AND (p.polname LIKE '%\_1939%' ESCAPE E'\\'
           OR p.polname LIKE '%\_2018%' ESCAPE E'\\')
  ), drift AS (
    SELECT 'additional' AS drift_kind,actual.* FROM actual
    EXCEPT
    SELECT 'additional',expected.* FROM expected
    UNION ALL
    SELECT 'omitted' AS drift_kind,expected.* FROM expected
    EXCEPT
    SELECT 'omitted',actual.* FROM actual
  )
  SELECT jsonb_agg(
           jsonb_build_object(
             'drift',drift_kind,'kind',object_kind,'schema',object_schema,
             'name',object_name,'parent',parent_identity
           ) ORDER BY drift_kind,object_kind,object_schema,object_name,parent_identity
         )
    INTO v_drift
    FROM drift;

  IF v_drift IS NOT NULL THEN
    RAISE EXCEPTION 'REIMPORT_EDITION_OBJECT_ALLOWLIST_DRIFT';
  END IF;
END
$assert_reimport_edition_catalog$;

REVOKE ALL ON FUNCTION private.assert_reimport_edition_catalog() FROM PUBLIC,anon,authenticated,service_role;

DO $verify_reimport_writer_task9_surface$
DECLARE v_signature text;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'private.validate_reimport_writer_config(jsonb)',
    'public.red_apply_reimport_canonical_delta(uuid,text,jsonb)',
    'public.red_lock_reimport_name_completion(text,bigint,text)',
    'public.red_authorize_reimport_name_completion(text,uuid,text,text,bigint,text,text,jsonb,jsonb)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NULL THEN
      RAISE EXCEPTION 'REIMPORT_WRITER_TASK9_SURFACE_MISSING: %',v_signature;
    END IF;
  END LOOP;
  IF has_function_privilege('anon','public.red_apply_reimport_canonical_delta(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.red_lock_reimport_name_completion(text,bigint,text)','EXECUTE')
     OR has_function_privilege('anon','public.red_authorize_reimport_name_completion(text,uuid,text,text,bigint,text,text,jsonb,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_apply_reimport_canonical_delta(uuid,text,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_lock_reimport_name_completion(text,bigint,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.red_authorize_reimport_name_completion(text,uuid,text,text,bigint,text,text,jsonb,jsonb)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.red_authorize_reimport_name_completion(text,uuid,text,text,bigint,text,text,jsonb,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_TASK9_ACL_INVALID';
  END IF;
END $verify_reimport_writer_task9_surface$;

DO $verify_reimport_edition_catalog$
BEGIN
  PERFORM private.assert_reimport_edition_catalog();
  RAISE NOTICE 'OK: #153 edition-named reimport catalog is an exact allowlist';
END
$verify_reimport_edition_catalog$;

-- #152 Task 7: exact version/ACL/receipt cutover verification.
DO $verify_narrative_record_cutover$
DECLARE
  v_version integer;
  v_signature text;
  v_new text[]:=ARRAY[
    'public.red_upsert_person_narrative_record(bigint,bigint,text,text,boolean,text)',
    'public.red_publicer_person_narrative_record(bigint,bigint,text,text)',
    'public.red_revider_publiceret_person_narrative_record(bigint,bigint,text,text,text)',
    'public.red_revalider_person_narrative_record(bigint,bigint,text,text)',
    'public.red_kasser_person_narrative_record(bigint,bigint,text,text)',
    'public.red_tilbagetraek_person_narrative_record(bigint,bigint,text,text)',
    'public.red_tilbagetraek_legacy_narrative(uuid,text,text)',
    'public.red_fortryd_person_narrative_publication_event(uuid,text)'
  ];
  v_legacy_authenticated text[]:=ARRAY[
    'public.red_publicer_narrative_record(bigint,uuid,text,text)',
    'public.red_tilbagetraek_narrative_record(bigint)',
    'public.red_apply_reimport_cases(uuid,text,text)',
    'public.red_reverse_reimport_cases(uuid,uuid)'
  ];
  v_legacy_service text[]:=ARRAY[
    'public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)',
    'public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)'
  ];
  v_v2_facade_authenticated text[]:=ARRAY[
    'public.red_begin_1939_v50_reimport(uuid,text,text)',
    'public.red_apply_1939_v50_source_evidence(uuid,text,jsonb)',
    'public.red_apply_1939_v50_person_create(uuid,text,jsonb)',
    'public.red_apply_1939_v50_canonical_delta(uuid,text,jsonb)',
    'public.red_finalize_1939_v50_reimport(uuid)',
    'public.red_reverse_1939_v50_reimport(uuid,uuid)',
    'public.red_activate_1939_v50_batch(uuid,uuid)',
    'public.red_lock_1939_v50_name_completion(text)',
    'public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb)',
    'public.red_begin_1939_v50_name_completion(uuid,text,uuid)',
    'public.red_apply_1939_v50_name_completion(uuid,text,jsonb)',
    'public.red_finalize_1939_v50_name_completion(uuid)'
  ];
  v_v2_facade_service text[]:=ARRAY[
    'public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamptz)',
    'public.red_authorize_1939_v50_reversal(uuid,uuid,timestamptz)',
    'public.red_authorize_1939_v50_cutover(uuid,uuid,timestamptz)',
    'public.red_authorize_1939_v50_name_completion(text,uuid,text,text,jsonb,jsonb)'
  ];
BEGIN
  IF to_regclass('private.narrative_record_cutover_receipt') IS NULL
     OR to_regprocedure(
       'private.apply_narrative_record_cutover(text,text,text,text,text,text,uuid,text,text)'
     ) IS NULL
     OR to_regprocedure('private.apply_narrative_record_contract_acl(integer)') IS NULL THEN
    RAISE EXCEPTION 'VERIFY_NARRATIVE_RECORD_CUTOVER_OBJECT_MISSING';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class
           WHERE oid='private.narrative_record_cutover_receipt'::regclass)
     OR EXISTS (SELECT 1 FROM pg_policy
                 WHERE polrelid='private.narrative_record_cutover_receipt'::regclass) THEN
    RAISE EXCEPTION 'VERIFY_NARRATIVE_RECORD_CUTOVER_RECEIPT_RLS_INVALID';
  END IF;
  v_version:=public.narrative_record_contract_version();
  IF v_version NOT IN (1,2) THEN
    RAISE EXCEPTION 'VERIFY_NARRATIVE_RECORD_CONTRACT_VERSION_INVALID';
  END IF;
  FOREACH v_signature IN ARRAY v_new LOOP
    IF has_function_privilege('authenticated',v_signature,'EXECUTE') IS DISTINCT FROM
         (v_version=2)
       OR has_function_privilege('anon',v_signature,'EXECUTE')
       OR has_function_privilege('service_role',v_signature,'EXECUTE') THEN
      RAISE EXCEPTION 'VERIFY_NARRATIVE_RECORD_NEW_WRITER_ACL_INVALID: %',v_signature;
    END IF;
  END LOOP;
  FOREACH v_signature IN ARRAY v_legacy_authenticated LOOP
    IF has_function_privilege('authenticated',v_signature,'EXECUTE') IS DISTINCT FROM
         (v_version=1)
       OR has_function_privilege('anon',v_signature,'EXECUTE')
       OR has_function_privilege('service_role',v_signature,'EXECUTE') THEN
      RAISE EXCEPTION 'VERIFY_NARRATIVE_RECORD_LEGACY_AUTH_ACL_INVALID: %',v_signature;
    END IF;
  END LOOP;
  FOREACH v_signature IN ARRAY v_legacy_service LOOP
    IF has_function_privilege('service_role',v_signature,'EXECUTE') IS DISTINCT FROM
         (v_version=1)
       OR has_function_privilege('anon',v_signature,'EXECUTE')
       OR has_function_privilege('authenticated',v_signature,'EXECUTE') THEN
      RAISE EXCEPTION 'VERIFY_NARRATIVE_RECORD_LEGACY_SERVICE_ACL_INVALID: %',v_signature;
    END IF;
  END LOOP;
  FOREACH v_signature IN ARRAY v_v2_facade_authenticated LOOP
    IF has_function_privilege('authenticated',v_signature,'EXECUTE') IS DISTINCT FROM
         (v_version=2)
       OR has_function_privilege('anon',v_signature,'EXECUTE')
       OR has_function_privilege('service_role',v_signature,'EXECUTE') THEN
      RAISE EXCEPTION 'VERIFY_NARRATIVE_RECORD_V2_FACADE_AUTH_ACL_INVALID: %',v_signature;
    END IF;
  END LOOP;
  FOREACH v_signature IN ARRAY v_v2_facade_service LOOP
    IF has_function_privilege('service_role',v_signature,'EXECUTE') IS DISTINCT FROM
         (v_version=2)
       OR has_function_privilege('anon',v_signature,'EXECUTE')
       OR has_function_privilege('authenticated',v_signature,'EXECUTE') THEN
      RAISE EXCEPTION 'VERIFY_NARRATIVE_RECORD_V2_FACADE_SERVICE_ACL_INVALID: %',v_signature;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: narrative record contract v% ACL/receipt',v_version;
END
$verify_narrative_record_cutover$;

-- ===== #152 Task 3: record-keyed mutation kernel, additive ACL =====
DO $narrative_record_mutation_verify$
DECLARE
  v_signature text;
  v_role text;
  v_definition text;
  v_lock_position integer;
  v_version_position integer;
  v_state_position integer;
BEGIN
  IF public.narrative_record_contract_version() NOT IN (1,2) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_MUTATION_ADDITIVE_VERSION_INVALID';
  END IF;

  FOREACH v_signature IN ARRAY ARRAY[
    'private.mutate_person_narrative_record(text,bigint,bigint,text,text,boolean,text)',
    'public.red_upsert_person_narrative_record(bigint,bigint,text,text,boolean,text)',
    'public.red_publicer_person_narrative_record(bigint,bigint,text,text)',
    'public.red_revider_publiceret_person_narrative_record(bigint,bigint,text,text,text)',
    'public.red_revalider_person_narrative_record(bigint,bigint,text,text)',
    'public.red_kasser_person_narrative_record(bigint,bigint,text,text)',
    'public.red_tilbagetraek_person_narrative_record(bigint,bigint,text,text)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NULL THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_MUTATION_FUNCTION_MISSING: %',v_signature;
    END IF;
    IF pg_get_function_result(to_regprocedure(v_signature)) IS DISTINCT FROM 'jsonb' THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_MUTATION_RESULT_INVALID: %',v_signature;
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      IF has_function_privilege(v_role,v_signature,'EXECUTE') IS DISTINCT FROM (
        public.narrative_record_contract_version()=2
        AND v_role='authenticated'
        AND v_signature LIKE 'public.%'
      ) THEN
        RAISE EXCEPTION 'NARRATIVE_RECORD_MUTATION_PRECUTOVER_ACL_INVALID: % %',
          v_role,v_signature;
      END IF;
    END LOOP;
  END LOOP;

  IF EXISTS (
    SELECT 1
      FROM pg_proc function
     WHERE function.oid IN (
       'private.mutate_person_narrative_record(text,bigint,bigint,text,text,boolean,text)'::regprocedure,
       'public.red_upsert_person_narrative_record(bigint,bigint,text,text,boolean,text)'::regprocedure,
       'public.red_publicer_person_narrative_record(bigint,bigint,text,text)'::regprocedure,
       'public.red_revider_publiceret_person_narrative_record(bigint,bigint,text,text,text)'::regprocedure,
       'public.red_revalider_person_narrative_record(bigint,bigint,text,text)'::regprocedure,
       'public.red_kasser_person_narrative_record(bigint,bigint,text,text)'::regprocedure,
       'public.red_tilbagetraek_person_narrative_record(bigint,bigint,text,text)'::regprocedure
     )
       AND (
         NOT function.prosecdef
         OR function.provolatile<>'v'
         OR function.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[]
       )
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_MUTATION_SECURITY_INVALID';
  END IF;

  v_definition:=pg_get_functiondef(
    'private.mutate_person_narrative_record(text,bigint,bigint,text,text,boolean,text)'::regprocedure
  );
  v_lock_position:=strpos(v_definition,'pg_advisory_xact_lock_shared(');
  v_version_position:=strpos(v_definition,'public.narrative_record_contract_version()');
  v_state_position:=strpos(v_definition,'private.narrative_record_state(');
  IF v_lock_position=0 OR v_version_position<=v_lock_position
     OR v_state_position<=v_version_position
     OR strpos(v_definition,'''daa-narrative-record-contract''')=0 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_MUTATION_GATE_OR_LOCK_ORDER_INVALID';
  END IF;

  IF NOT has_function_privilege(
    'authenticated','public.red_person_narrative_records(bigint)','EXECUTE'
  ) OR NOT has_function_privilege(
    'authenticated','public.red_person_narrative_publication_history(bigint)','EXECUTE'
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_MUTATION_EDITOR_READ_ACL_REGRESSION';
  END IF;

  RAISE NOTICE 'OK: #152 Task 3 mutation kernel ACL matcher contract-version %',
    public.narrative_record_contract_version();
END
$narrative_record_mutation_verify$;

-- ===== #152 Task 4: legacy withdrawal, dedicated reversal and undo routing =====
DO $narrative_record_reversal_verify$
DECLARE
  v_signature text;
  v_role text;
  v_definition text;
  v_lock_position integer;
  v_version_position integer;
  v_guard_position integer;
  v_change_set_position integer;
BEGIN
  IF public.narrative_record_contract_version() NOT IN (1,2) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_REVERSAL_ADDITIVE_VERSION_INVALID';
  END IF;

  FOREACH v_signature IN ARRAY ARRAY[
    'private.withdraw_legacy_narrative(uuid,text,text)',
    'private.reverse_narrative_publication_event(uuid,text)',
    'public.red_tilbagetraek_legacy_narrative(uuid,text,text)',
    'public.red_fortryd_person_narrative_publication_event(uuid,text)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NULL THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_REVERSAL_FUNCTION_MISSING: %',v_signature;
    END IF;
    IF pg_get_function_result(to_regprocedure(v_signature)) IS DISTINCT FROM 'jsonb' THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_REVERSAL_RESULT_INVALID: %',v_signature;
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      IF has_function_privilege(v_role,v_signature,'EXECUTE') IS DISTINCT FROM (
        public.narrative_record_contract_version()=2
        AND v_role='authenticated'
        AND v_signature LIKE 'public.%'
      ) THEN
        RAISE EXCEPTION 'NARRATIVE_RECORD_REVERSAL_PRECUTOVER_ACL_INVALID: % %',
          v_role,v_signature;
      END IF;
    END LOOP;
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM pg_proc function
     WHERE function.oid IN (
       'private.withdraw_legacy_narrative(uuid,text,text)'::regprocedure,
       'private.reverse_narrative_publication_event(uuid,text)'::regprocedure,
       'public.red_tilbagetraek_legacy_narrative(uuid,text,text)'::regprocedure,
       'public.red_fortryd_person_narrative_publication_event(uuid,text)'::regprocedure
     )
       AND (
         NOT function.prosecdef OR function.provolatile<>'v'
         OR function.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[]
       )
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_REVERSAL_SECURITY_INVALID';
  END IF;

  v_definition:=pg_get_functiondef(
    'private.withdraw_legacy_narrative(uuid,text,text)'::regprocedure
  );
  v_lock_position:=strpos(v_definition,'pg_advisory_xact_lock_shared(');
  v_version_position:=strpos(v_definition,'public.narrative_record_contract_version()');
  IF v_lock_position=0 OR v_version_position<=v_lock_position
     OR strpos(v_definition,'private.narrative_legacy_state(')<=v_version_position THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_LEGACY_WITHDRAWAL_LOCK_ORDER_INVALID';
  END IF;

  v_definition:=pg_get_functiondef(
    'private.reverse_narrative_publication_event(uuid,text)'::regprocedure
  );
  v_lock_position:=strpos(v_definition,'pg_advisory_xact_lock_shared(');
  v_version_position:=strpos(v_definition,'public.narrative_record_contract_version()');
  IF v_lock_position=0 OR v_version_position<=v_lock_position
     OR strpos(v_definition,'private.narrative_record_state(')<=v_version_position
     OR strpos(v_definition,'private.narrative_legacy_state(')<=v_version_position THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_REVERSAL_LOCK_ORDER_INVALID';
  END IF;

  v_definition:=pg_get_functiondef(
    'public.red_fortryd_change_set(bigint,boolean)'::regprocedure
  );
  v_lock_position:=strpos(
    v_definition,'LOCK TABLE public.change_set IN ACCESS SHARE MODE'
  );
  v_guard_position:=strpos(
    v_definition,'NARRATIVE_RECORD_DEDICATED_REVERSAL_REQUIRED'
  );
  v_change_set_position:=strpos(v_definition,'INSERT INTO change_set');
  IF v_lock_position=0 OR v_guard_position<=v_lock_position
     OR v_change_set_position=0
     OR v_guard_position>=v_change_set_position THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_GENERIC_UNDO_ROUTING_INVALID';
  END IF;

  v_definition:=pg_get_functiondef('public.red_slet_person(bigint)'::regprocedure);
  v_lock_position:=strpos(v_definition,'pg_advisory_xact_lock_shared(');
  v_guard_position:=strpos(
    v_definition,'PERSON_HAR_NARRATIVE_PUBLICATION_HISTORY'
  );
  v_change_set_position:=strpos(v_definition,'begin_change_set(');
  IF v_lock_position=0 OR v_guard_position<=v_lock_position
     OR v_change_set_position<=v_guard_position THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_PERSON_DELETE_ROUTING_INVALID';
  END IF;

  v_definition:=pg_get_functiondef(
    'public.red_person_narrative_publication_history(bigint)'::regprocedure
  );
  IF strpos(v_definition,'NARRATIVE_PUBLICATION_REVERSAL_NOT_REVERSIBLE')=0 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_HISTORY_REVERSAL_REASON_INVALID';
  END IF;
  IF strpos(v_definition,'NARRATIVE_PUBLICATION_EVENT_NOT_REVERSIBLE')=0
     OR strpos(v_definition,'classified.event_type NOT IN')=0 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_HISTORY_LEGAL_EVENT_SET_INVALID';
  END IF;

  RAISE NOTICE 'OK: #152 Task 4 withdrawal/reversal ACL matcher contract-version %',
    public.narrative_record_contract_version();
END
$narrative_record_reversal_verify$;

-- ===== #152 Task 5: event-gated public v2 contract and narrative RLS =====
DO $narrative_record_public_read_verify$
DECLARE
  v_signature text;
  v_role text;
  v_definition text;
  v_policy text;
  v_result text;
  v_expected_owner oid;
  v_privilege text;
BEGIN
  IF public.narrative_record_contract_version() NOT IN (1,2) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLIC_READ_ADDITIVE_VERSION_INVALID';
  END IF;
  IF to_regprocedure(
       'public.person_daa_narrative_publication_allowed(bigint)'
     ) IS NULL
     OR to_regprocedure(
       'public.public_person_bio_source_versions_v2(bigint[])'
     ) IS NULL THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLIC_READ_CONTRACT_MISSING';
  END IF;

  SELECT pg_get_function_result(
    'public.public_person_bio_source_versions_v2(bigint[])'::regprocedure
  ) INTO v_result;
  IF v_result IS DISTINCT FROM
       'TABLE(person_id bigint, source_id bigint, source_year integer, record_order integer, source_record_ref uuid, source_label text, record_label text, narrative_text text, citation_label text, provenance_kind text)' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLIC_V2_RESULT_INVALID: %',v_result;
  END IF;

  SELECT relation.relowner INTO v_expected_owner
    FROM pg_class relation WHERE relation.oid='public.narrative'::regclass;
  IF v_expected_owner IS DISTINCT FROM (
       SELECT relation.relowner FROM pg_class relation
        WHERE relation.oid='private.narrative_publication_event'::regclass
     ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLIC_CONTROLLED_OWNER_SPLIT';
  END IF;

  FOREACH v_signature IN ARRAY ARRAY[
    'public.person_daa_narrative_publication_allowed(bigint)',
    'public.public_person_bio_source_versions(bigint[])',
    'public.public_person_bio_source_versions_v2(bigint[])'
  ] LOOP
    IF EXISTS (
      SELECT 1 FROM pg_proc function
       JOIN pg_roles owner ON owner.oid=function.proowner
       WHERE function.oid=v_signature::regprocedure
         AND (
           NOT function.prosecdef
           OR function.provolatile<>'s'
           OR function.proconfig IS DISTINCT FROM
                ARRAY['search_path=pg_catalog']::text[]
           OR function.proowner<>v_expected_owner
         )
    ) THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLIC_FUNCTION_SECURITY_INVALID: %',
        v_signature;
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
      IF NOT has_function_privilege(v_role,v_signature,'EXECUTE') THEN
        RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLIC_FUNCTION_GRANT_MISSING: % %',
          v_role,v_signature;
      END IF;
    END LOOP;
    IF EXISTS (
         SELECT 1
           FROM pg_proc function
           CROSS JOIN LATERAL aclexplode(
             coalesce(function.proacl,acldefault('f',function.proowner))
           ) acl
          WHERE function.oid=v_signature::regprocedure
            AND (
              acl.privilege_type<>'EXECUTE'
              OR acl.is_grantable
              OR acl.grantor<>v_expected_owner
              OR acl.grantee NOT IN (
                v_expected_owner,'anon'::regrole::oid,
                'authenticated'::regrole::oid
              )
            )
       ) OR (
         SELECT count(*)
           FROM pg_proc function
           CROSS JOIN LATERAL aclexplode(
             coalesce(function.proacl,acldefault('f',function.proowner))
           ) acl
          WHERE function.oid=v_signature::regprocedure
       )<>3 THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLIC_FUNCTION_GRANT_INVALID: %',
        v_signature;
    END IF;
  END LOOP;

  v_definition:=pg_get_functiondef(
    'public.person_daa_narrative_publication_allowed(bigint)'::regprocedure
  );
  IF strpos(v_definition,'private.narrative_publication_state(')=0
     OR strpos(v_definition,'private.narrative_legacy_publication_state(')=0
     OR strpos(v_definition,'private.narrative_record_state(')>0
     OR strpos(v_definition,'private.narrative_legacy_state(')>0 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLIC_PREDICATE_STATE_INVALID';
  END IF;
  FOREACH v_signature IN ARRAY ARRAY[
    'public.public_person_bio_source_versions(bigint[])',
    'public.public_person_bio_source_versions_v2(bigint[])'
  ] LOOP
    v_definition:=pg_get_functiondef(v_signature::regprocedure);
    IF strpos(v_definition,'person_daa_narrative_publication_allowed')=0
       OR strpos(v_definition,'narrative_record_contract_version()')=0 THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLIC_RPC_GATE_INVALID: %',v_signature;
    END IF;
  END LOOP;

  IF NOT (
    SELECT relation.relrowsecurity AND NOT relation.relforcerowsecurity
      FROM pg_class relation WHERE relation.oid='public.narrative'::regclass
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLIC_RLS_MODE_INVALID';
  END IF;
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    SELECT pg_get_expr(policy.polqual,policy.polrelid)
      INTO v_policy
      FROM pg_policy policy
     WHERE policy.polrelid='public.narrative'::regclass
       AND policy.polname=CASE v_role
         WHEN 'anon' THEN 'anon_read' ELSE 'auth_read' END;
    IF strpos(
         coalesce(v_policy,''),'person_daa_narrative_publication_allowed'
       )=0 THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLIC_RLS_POLICY_INVALID: % %',
        v_role,v_policy;
    END IF;
  END LOOP;

  FOREACH v_signature IN ARRAY ARRAY[
    'private.narrative_record_publication',
    'private.narrative_publication_event',
    'private.narrative_legacy_publication'
  ] LOOP
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      FOREACH v_privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE'] LOOP
        IF has_table_privilege(v_role,v_signature,v_privilege) THEN
          RAISE EXCEPTION
            'NARRATIVE_RECORD_PUBLIC_PRIVATE_TABLE_GRANT: % % %',
            v_role,v_signature,v_privilege;
        END IF;
      END LOOP;
    END LOOP;
    IF EXISTS (
      SELECT 1
        FROM pg_class relation
        CROSS JOIN LATERAL aclexplode(
          coalesce(relation.relacl,acldefault('r',relation.relowner))
        ) acl
       WHERE relation.oid=v_signature::regclass
         AND acl.grantee=0
         AND acl.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')
    ) THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLIC_PRIVATE_TABLE_GRANT: PUBLIC %',
        v_signature;
    END IF;
  END LOOP;

  RAISE NOTICE 'OK: #152 Task 5 public v1/v2, semantic predicate og RLS er installeret';
END
$narrative_record_public_read_verify$;

-- ===== C3 apply plan Task 5: generic reimport case ledger contract =====
-- Full catalog/constraint proof lives in tests/sql/test-1939-v50-c3-apply.sql; this
-- block only proves the objects exist and stay private after db-migrations.sql/db-rls.sql.
DO $$
BEGIN
  IF to_regclass('private.reimport_case_authorization') IS NULL
     OR to_regclass('private.reimport_case_batch') IS NULL
     OR to_regclass('private.reimport_case_event') IS NULL
     OR to_regclass('private.narrative_record_publication_active_record_uidx') IS NULL
     OR to_regprocedure('private.reject_reimport_case_event_mutation()') IS NULL THEN
    RAISE EXCEPTION 'C3_APPLY_LEDGER_CONTRACT_MISSING';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE']) privilege
    CROSS JOIN unnest(ARRAY[
      'private.reimport_case_authorization','private.reimport_case_batch','private.reimport_case_event'
    ]) tbl
    WHERE has_table_privilege('anon',tbl,privilege)
       OR has_table_privilege('authenticated',tbl,privilege)
  ) THEN
    RAISE EXCEPTION 'C3_APPLY_LEDGER_PRIVATE_GRANT_INVALID';
  END IF;
  RAISE NOTICE 'OK: C3 apply case ledger (reimport_case_authorization/_batch/_event) er installeret og privat';
END $$;

-- ===== C3 apply plan Task 6: atomic apply RPC contract =====
-- Behavioural proof lives in tests/sql/test-1939-v50-c3-apply.sql; this block only
-- proves the deployed surface after db-migrations.sql/db-rls.sql: the three entry
-- points exist with their exact signatures, preview is STABLE, all three are
-- SECURITY DEFINER with a fixed search_path, the ACL split holds (preview+apply to
-- authenticated, authorize to service_role, nothing to PUBLIC/anon), every private
-- helper stays ungranted, and red_publicer_narrative_record still takes fund B4's
-- source-record lock BEFORE it reads the binding row.
DO $$
DECLARE v_def text; v_lock int; v_select int; v_apply_def text;
BEGIN
  IF to_regprocedure('public.red_preview_reimport_cases(bigint,text,jsonb)') IS NULL
     OR to_regprocedure('public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)') IS NULL
     OR to_regprocedure('public.red_apply_reimport_cases(uuid,text,text)') IS NULL
     OR to_regprocedure('private.reimport_case_receipt(uuid)') IS NULL
     OR to_regprocedure('private.write_reimport_case_narrative(bigint,bigint,bigint,text,boolean,text)') IS NULL
     OR to_regprocedure('private.reimport_case_source_record_state(bigint,text)') IS NULL
     OR to_regprocedure('private.reimport_case_narrative_state(bigint,bigint)') IS NULL
     OR to_regprocedure('private.reimport_case_binding_state(uuid,bigint)') IS NULL
     OR to_regprocedure('private.validate_reimport_case_selection(jsonb)') IS NULL
     OR to_regprocedure('private.validate_reimport_case_elements(jsonb,jsonb)') IS NULL
     OR to_regprocedure('private.validate_reimport_case_counts(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'C3_APPLY_RPC_CONTRACT_MISSING';
  END IF;
  IF (SELECT provolatile FROM pg_proc
       WHERE oid='public.red_preview_reimport_cases(bigint,text,jsonb)'::regprocedure) <> 's' THEN
    RAISE EXCEPTION 'C3_APPLY_PREVIEW_NOT_STABLE';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p WHERE p.oid IN (
      'public.red_preview_reimport_cases(bigint,text,jsonb)'::regprocedure,
      'public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)'::regprocedure,
      'public.red_apply_reimport_cases(uuid,text,text)'::regprocedure)
      AND (NOT p.prosecdef OR p.proconfig IS NULL)
  ) THEN
    RAISE EXCEPTION 'C3_APPLY_RPC_HARDENING_MISSING';
  END IF;
  IF has_function_privilege('anon','public.red_preview_reimport_cases(bigint,text,jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.red_apply_reimport_cases(uuid,text,text)','EXECUTE')
     OR has_function_privilege('anon','public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)','EXECUTE')
     OR has_function_privilege('authenticated','public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)','EXECUTE')
     OR has_function_privilege('service_role','public.red_apply_reimport_cases(uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_preview_reimport_cases(bigint,text,jsonb)','EXECUTE')
     OR has_function_privilege(
       'authenticated','public.red_apply_reimport_cases(uuid,text,text)','EXECUTE'
     ) IS DISTINCT FROM (public.narrative_record_contract_version()=1)
     OR has_function_privilege(
       'service_role',
       'public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)',
       'EXECUTE'
     ) IS DISTINCT FROM (public.narrative_record_contract_version()=1) THEN
    RAISE EXCEPTION 'C3_APPLY_RPC_ACL_INVALID';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(ARRAY[
      'private.reimport_case_source_record_state(bigint,text)',
      'private.reimport_case_narrative_state(bigint,bigint)',
      'private.reimport_case_binding_state(uuid,bigint)',
      'private.validate_reimport_case_selection(jsonb)',
      'private.validate_reimport_case_elements(jsonb,jsonb)',
      'private.validate_reimport_case_counts(jsonb)',
      'private.reimport_case_receipt(uuid)',
      'private.write_reimport_case_narrative(bigint,bigint,bigint,text,boolean,text)']) fn
    CROSS JOIN unnest(ARRAY['anon','authenticated','service_role']) role_name
    WHERE has_function_privilege(role_name,fn,'EXECUTE')
  ) THEN
    RAISE EXCEPTION 'C3_APPLY_PRIVATE_HELPER_ACL_INVALID';
  END IF;
  v_def := pg_get_functiondef('public.red_publicer_narrative_record(bigint,uuid,text,text)'::regprocedure);
  v_lock := strpos(v_def,'FROM private.source_record WHERE id = p_source_record_id FOR UPDATE');
  v_select := strpos(v_def,'FROM private.narrative_record_publication');
  IF v_lock = 0 OR v_select = 0 OR v_lock > v_select THEN
    RAISE EXCEPTION 'C3_APPLY_PUBLICATION_SOURCE_RECORD_LOCK_MISSING';
  END IF;
  -- lock_timeout/statement_timeout must be set BEFORE the step-1 advisory lock
  -- (lock_timeout is re-read at every lock acquisition, so its position decides
  -- whether step 1's own wait is bounded), and the foreign-change-set guard
  -- must run before begin_change_set, which would otherwise silently return an
  -- already active change set and enrol the whole batch into it.
  v_apply_def := pg_get_functiondef('public.red_apply_reimport_cases(uuid,text,text)'::regprocedure);
  IF strpos(v_apply_def,'set_config(''lock_timeout''') = 0
     OR strpos(v_apply_def,'set_config(''statement_timeout''') = 0
     OR strpos(v_apply_def,'hashtextextended(''daa-1939-v50-production-writer'',0)') = 0
     OR strpos(v_apply_def,'set_config(''lock_timeout''')
        > strpos(v_apply_def,'hashtextextended(''daa-1939-v50-production-writer'',0)')
     OR strpos(v_apply_def,'set_config(''statement_timeout''')
        > strpos(v_apply_def,'hashtextextended(''daa-1939-v50-production-writer'',0)') THEN
    RAISE EXCEPTION 'C3_APPLY_TIMEOUTS_SET_TOO_LATE';
  END IF;
  IF strpos(v_apply_def,'REIMPORT_CASE_FOREIGN_CHANGE_SET') = 0
     OR strpos(v_apply_def,'public.begin_change_set(') = 0
     OR strpos(v_apply_def,'REIMPORT_CASE_FOREIGN_CHANGE_SET')
        > strpos(v_apply_def,'public.begin_change_set(') THEN
    RAISE EXCEPTION 'C3_APPLY_FOREIGN_CHANGE_SET_GUARD_MISSING';
  END IF;
  RAISE NOTICE 'OK: C3 apply RPC-kontrakt (preview/authorize/apply) er installeret, hærdet og rolle-adskilt';
END $$;

-- ===== C3 Task 7 — reversal-RPC-kontrakt =====
-- Reversal er sin EGEN batch (fund B5): egen authorization, egen nonce, eget
-- change set og egen kvittering. Kontrakten her er den deployede flade:
-- signaturer, hærdning, rolle-adskillelse (service_role autoriserer,
-- authenticated reverserer), samme låsepræfiks som apply, og at HELE CAS'en
-- ligger før første mutation -- den ene påstand en enkelt-session-test ikke selv
-- kan bevise, fordi et fejlet kalds egen sub-transaktion rulles tilbage.
DO $$
DECLARE v_def text; v_cas int; v_first_write int; v_bindings int; v_fortryd int;
BEGIN
  IF to_regprocedure('public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)') IS NULL
     OR to_regprocedure('public.red_reverse_reimport_cases(uuid,uuid)') IS NULL
     OR to_regprocedure('private.reimport_case_reversal_plan(uuid)') IS NULL THEN
    RAISE EXCEPTION 'C3_REVERSAL_RPC_CONTRACT_MISSING';
  END IF;
  IF (SELECT provolatile FROM pg_proc
       WHERE oid='private.reimport_case_reversal_plan(uuid)'::regprocedure) <> 's' THEN
    RAISE EXCEPTION 'C3_REVERSAL_PLAN_NOT_STABLE';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p WHERE p.oid IN (
      'public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)'::regprocedure,
      'public.red_reverse_reimport_cases(uuid,uuid)'::regprocedure,
      'private.reimport_case_reversal_plan(uuid)'::regprocedure)
      AND (NOT p.prosecdef OR p.proconfig IS NULL)
  ) THEN
    RAISE EXCEPTION 'C3_REVERSAL_RPC_HARDENING_MISSING';
  END IF;
  IF has_function_privilege('anon','public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)','EXECUTE')
     OR has_function_privilege('anon','public.red_reverse_reimport_cases(uuid,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)','EXECUTE')
     OR has_function_privilege('service_role','public.red_reverse_reimport_cases(uuid,uuid)','EXECUTE')
     OR has_function_privilege(
       'service_role','public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)',
       'EXECUTE'
     ) IS DISTINCT FROM (public.narrative_record_contract_version()=1)
     OR has_function_privilege(
       'authenticated','public.red_reverse_reimport_cases(uuid,uuid)','EXECUTE'
     ) IS DISTINCT FROM (public.narrative_record_contract_version()=1) THEN
    RAISE EXCEPTION 'C3_REVERSAL_RPC_ACL_INVALID';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
    WHERE has_function_privilege(role_name,'private.reimport_case_reversal_plan(uuid)','EXECUTE')
  ) THEN
    RAISE EXCEPTION 'C3_REVERSAL_PLAN_ACL_INVALID';
  END IF;
  v_def := pg_get_functiondef('public.red_reverse_reimport_cases(uuid,uuid)'::regprocedure);
  -- Samme låsepræfiks som apply: timeouts og fremmed-change-set-gate før den
  -- globale writer-lås, og PRÆCIS samme advisory-nøgle -- ellers kan en apply og
  -- en reversal køre samtidig.
  IF strpos(v_def,'set_config(''lock_timeout''') = 0
     OR strpos(v_def,'set_config(''statement_timeout''') = 0
     OR strpos(v_def,'REIMPORT_CASE_FOREIGN_CHANGE_SET') = 0
     OR strpos(v_def,'hashtextextended(''daa-1939-v50-production-writer'',0)') = 0
     OR strpos(v_def,'set_config(''lock_timeout''')
        > strpos(v_def,'hashtextextended(''daa-1939-v50-production-writer'',0)')
     OR strpos(v_def,'REIMPORT_CASE_FOREIGN_CHANGE_SET')
        > strpos(v_def,'hashtextextended(''daa-1939-v50-production-writer'',0)')
     OR strpos(v_def,'hashtext(''samme_som_mutation'')')
        < strpos(v_def,'hashtextextended(''daa-1939-v50-production-writer'',0)') THEN
    RAISE EXCEPTION 'C3_REVERSAL_LOCK_PREFIX_INVALID';
  END IF;
  -- Hele CAS'en før første mutation; bindinger før change-set-undoet (binding
  -- -> narrative er en almindelig FK uden ON DELETE); ingen force-omgåelse.
  v_cas         := strpos(v_def,'reversal CAS: everything is proven BEFORE the first mutation');
  v_first_write := strpos(v_def,'INSERT INTO private.reimport_case_batch(');
  v_bindings    := strpos(v_def,'DELETE FROM private.narrative_record_publication');
  v_fortryd     := strpos(v_def,'public.red_fortryd_change_set(');
  IF v_cas = 0 OR v_first_write = 0 OR v_bindings = 0 OR v_fortryd = 0
     OR v_cas > v_first_write OR v_bindings > v_fortryd THEN
    RAISE EXCEPTION 'C3_REVERSAL_MUTATION_ORDER_INVALID';
  END IF;
  IF strpos(v_def,'red_fortryd_change_set(v_change_set,false)') = 0
     OR strpos(v_def,'red_fortryd_change_set(v_change_set,true)') <> 0 THEN
    RAISE EXCEPTION 'C3_REVERSAL_FORCE_BYPASS_PRESENT';
  END IF;
  RAISE NOTICE 'OK: C3 reversal-RPC-kontrakt (authorize/reverse) er installeret, hærdet, rolle-adskilt og CAS-før-mutation';
END $$;

-- ===== C3 Task 1 — komponentbrede identitetskontradiktioner =====
DO $$
BEGIN
  IF to_regclass('private.identity_mutation_generation') IS NULL
     OR to_regprocedure('private.guard_identity_mutation_snapshot()') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_proc p
       WHERE p.oid='private.guard_identity_mutation_snapshot()'::regprocedure
         AND p.prosecdef
         AND 'search_path=pg_catalog, private'=ANY(p.proconfig)
     ) THEN
    RAISE EXCEPTION 'IDENTITY_MUTATION_GENERATION_CONTRACT_MISSING';
  END IF;
  IF has_table_privilege('anon','private.identity_mutation_generation','SELECT')
     OR has_table_privilege('authenticated','private.identity_mutation_generation','UPDATE')
     OR has_function_privilege('anon','private.guard_identity_mutation_snapshot()','EXECUTE')
     OR has_function_privilege('authenticated','private.guard_identity_mutation_snapshot()','EXECUTE') THEN
    RAISE EXCEPTION 'IDENTITY_MUTATION_GENERATION_ACL_DRIFT';
  END IF;
  IF EXISTS (
    SELECT 1 FROM (VALUES
      ('public.relation_id_seq'),('public.assertion_id_seq'),('public.conclusion_id_seq')
    ) s(name), (VALUES ('PUBLIC'),('anon'),('authenticated')) r(name)
    WHERE (r.name='PUBLIC' AND EXISTS (
             SELECT 1 FROM pg_class c
             CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('S',c.relowner))) a
             WHERE c.oid=s.name::regclass AND a.grantee=0
               AND a.privilege_type IN ('USAGE','SELECT','UPDATE')
          )) OR (r.name<>'PUBLIC' AND (
             has_sequence_privilege(r.name,s.name,'USAGE')
             OR has_sequence_privilege(r.name,s.name,'SELECT')
             OR has_sequence_privilege(r.name,s.name,'UPDATE')
          ))
  ) THEN
    RAISE EXCEPTION 'IDENTITY_SEQUENCE_ACL_DRIFT';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid = 'private.identity_components_have_rejection(bigint,bigint)'::regprocedure
      AND p.prosecdef
      AND 'search_path=pg_catalog, public, private' = ANY (p.proconfig)
  ) THEN
    RAISE EXCEPTION 'IDENTITY_COMPONENT_HELPER_SECURITY_DRIFT';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f',p.proowner))) acl
    WHERE p.oid = 'private.identity_components_have_rejection(bigint,bigint)'::regprocedure
      AND acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
  )
     OR has_function_privilege('anon','private.identity_components_have_rejection(bigint,bigint)','EXECUTE')
     OR has_function_privilege('authenticated','private.identity_components_have_rejection(bigint,bigint)','EXECUTE') THEN
    RAISE EXCEPTION 'IDENTITY_COMPONENT_HELPER_ACL_DRIFT';
  END IF;
  RAISE NOTICE 'OK: C3 identitets-helper er DEFINER, har fast search_path og er privat';
END $$;

BEGIN;
DO $verify$
DECLARE
  v_actor uuid := '19390000-0000-4000-8000-000000000002';
  a1 bigint := -1939502001; a2 bigint := -1939502002; ac bigint := -1939502003;
  b1 bigint := -1939502004; b2 bigint := -1939502005; bc bigint := -1939502006;
  u1 bigint := -1939502007; uc bigint := -1939502008; v1 bigint := -1939502009;
  w1 bigint := -1939502010; w2 bigint := -1939502011; wc bigint := -1939502012;
  x1 bigint := -1939502013; x2 bigint := -1939502014;
  v_rejection bigint; v_remove_change_set bigint; v_update_rejection bigint;
  v_current jsonb; v_target jsonb;
BEGIN
  INSERT INTO auth.users(id,email)
  VALUES (v_actor,'c3-identity-verify@test.invalid')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,email,rolle,navn)
  VALUES (v_actor,'c3-identity-verify@test.invalid','redaktion','C3 identity verify')
  ON CONFLICT (id) DO UPDATE SET rolle='redaktion', navn='C3 identity verify';
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  INSERT INTO person(id,levende,koen) VALUES
    (a1,false,'mand'), (a2,false,'mand'), (ac,false,'mand'),
    (b1,false,'kvinde'), (b2,false,'kvinde'), (bc,false,'kvinde'),
    (u1,false,'mand'), (uc,false,'mand'), (v1,false,'kvinde'),
    (w1,false,'mand'), (w2,false,'kvinde'), (wc,false,'mand'),
    (x1,false,'ukendt'), (x2,false,'ukendt')
  ON CONFLICT (id) DO NOTHING;

  PERFORM red_samme_som(a1,ac);
  PERFORM red_samme_som(a2,ac);
  BEGIN
    INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM relation),
            'person',a1,'person',a2,'ikke_samme_som');
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_TRIGGER_COMPONENT_DIFFERENT_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%IDENTITY_COMPONENT_CONTRADICTION%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM red_ikke_samme_som(a1,a2);
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_COMPONENT_DIFFERENT_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%IDENTITY_COMPONENT_CONTRADICTION%' THEN RAISE; END IF;
  END;

  PERFORM red_samme_som(b1,bc);
  PERFORM red_samme_som(b2,bc);
  PERFORM red_ikke_samme_som(a1,b1);
  BEGIN
    PERFORM red_samme_som(a2,b2);
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_COMPONENT_SAME_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%IDENTITY_COMPONENT_CONTRADICTION%' THEN RAISE; END IF;
  END;
  v_update_rejection := red_ikke_samme_som(w1,w2);
  PERFORM red_samme_som(w1,wc);
  SELECT to_jsonb(r) INTO v_current FROM relation r WHERE r.id=v_update_rejection;
  v_target := v_current || jsonb_build_object('subjekt_id',w1,'objekt_id',wc);
  BEGIN
    PERFORM private.prelock_identity_relation_update(v_current,v_target);
    UPDATE relation SET subjekt_id=w1, objekt_id=wc WHERE id=v_update_rejection;
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_COMPONENT_UPDATE_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%IDENTITY_COMPONENT_CONTRADICTION%' THEN RAISE; END IF;
  END;

  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  PERFORM red_samme_som(u1,uc);
  v_rejection := red_ikke_samme_som(u1,v1);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  PERFORM red_fjern_ikke_samme_som(v_rejection);
  v_remove_change_set := current_setting('app.change_set_id',true)::bigint;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  PERFORM red_ikke_samme_som(x1,x2);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  PERFORM red_samme_som(v1,uc);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  BEGIN
    -- This fixture's preceding identity writers may materialize a change_set
    -- with an explicit ID.  Keep the owned sequence in step before the undo
    -- writer performs its normal automatic INSERT, so this verifier exercises
    -- the intended contradiction path rather than a fixture-only PK collision.
    PERFORM setval(
      pg_get_serial_sequence('public.change_set','id'),
      (SELECT coalesce(max(id),1) FROM public.change_set),
      true
    );
    PERFORM red_fortryd_change_set(v_remove_change_set,true);
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_UNDO_COMPONENT_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%IDENTITY_COMPONENT_CONTRADICTION%' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claim.sub','19390000-0000-4000-8000-000000000098',true);
  BEGIN
    PERFORM private.identity_components_have_rejection(a1,b1);
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_HELPER_ROLE_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%Kun redaktion%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: C3 komponentbrede identitetskontradiktioner';
END $verify$;
ROLLBACK;

-- ===== C3 Task 2 — identitets-writers serialiserer med person-sletning =====
DO $verify$
DECLARE
  v_definition text;
  v_lock_position integer;
  v_people_position integer;
  v_writer regprocedure;
BEGIN
  IF to_regprocedure('private.lock_identity_people(bigint[])') IS NULL THEN
    RAISE EXCEPTION 'IDENTITY_LOCK_HELPER_MISSING';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid = 'private.lock_identity_people(bigint[])'::regprocedure
      AND p.prosecdef
      AND 'search_path=pg_catalog, public, private' = ANY (p.proconfig)
  ) THEN
    RAISE EXCEPTION 'IDENTITY_LOCK_HELPER_SECURITY_DRIFT';
  END IF;
  IF to_regprocedure('private.prelock_identity_relation_update(jsonb,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'IDENTITY_UPDATE_PRELOCK_HELPER_MISSING';
  END IF;
  IF to_regprocedure('private.prelock_identity_relation_delete(bigint)') IS NULL THEN
    RAISE EXCEPTION 'IDENTITY_DELETE_PRELOCK_HELPER_MISSING';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='private' AND table_name='identity_mutation_generation'
      AND column_name='guard_transaction_id' AND udt_name='xid8'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='private' AND table_name='identity_mutation_generation'
      AND column_name='guard_backend_pid' AND udt_name='int4'
  ) THEN
    RAISE EXCEPTION 'IDENTITY_DELETE_GUARD_PROOF_COLUMNS_MISSING';
  END IF;
  IF to_regclass('private.identity_relation_update_prelock') IS NULL THEN
    RAISE EXCEPTION 'IDENTITY_UPDATE_PRELOCK_RECORD_MISSING';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
    WHERE c.oid='private.identity_relation_update_prelock'::regclass
      AND c.relrowsecurity
  ) OR EXISTS (
    SELECT 1
    FROM pg_class c
    CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) acl
    WHERE c.oid='private.identity_relation_update_prelock'::regclass
      AND acl.grantee=0
  ) OR EXISTS (
    SELECT 1
    FROM unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) privilege
    WHERE has_table_privilege('anon','private.identity_relation_update_prelock',privilege)
       OR has_table_privilege('authenticated','private.identity_relation_update_prelock',privilege)
  ) THEN
    RAISE EXCEPTION 'IDENTITY_UPDATE_PRELOCK_RECORD_SECURITY_DRIFT';
  END IF;
  IF to_regprocedure('private.cleanup_identity_relation_update_prelock()') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_proc p
       WHERE p.oid='private.cleanup_identity_relation_update_prelock()'::regprocedure
         AND p.prosecdef
         AND 'search_path=pg_catalog, private'=ANY(p.proconfig)
     )
     OR EXISTS (
       SELECT 1
       FROM pg_proc p
       CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
       WHERE p.oid='private.cleanup_identity_relation_update_prelock()'::regprocedure
         AND acl.grantee=0 AND acl.privilege_type='EXECUTE'
     )
     OR has_function_privilege('anon','private.cleanup_identity_relation_update_prelock()','EXECUTE')
     OR has_function_privilege('authenticated','private.cleanup_identity_relation_update_prelock()','EXECUTE') THEN
    RAISE EXCEPTION 'IDENTITY_UPDATE_PRELOCK_CLEANUP_SECURITY_DRIFT';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='private.identity_relation_update_prelock'::regclass
      AND t.tgname='trg_identity_relation_update_prelock_cleanup'
      AND t.tgconstraint<>0
      AND t.tgdeferrable
      AND t.tginitdeferred
  ) THEN
    RAISE EXCEPTION 'IDENTITY_UPDATE_PRELOCK_CLEANUP_TRIGGER_DRIFT';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid = 'private.prelock_identity_relation_update(jsonb,jsonb)'::regprocedure
      AND p.prosecdef
      AND 'search_path=pg_catalog, public, private' = ANY (p.proconfig)
  ) OR has_function_privilege('anon','private.prelock_identity_relation_update(jsonb,jsonb)','EXECUTE')
       OR has_function_privilege('authenticated','private.prelock_identity_relation_update(jsonb,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'IDENTITY_UPDATE_PRELOCK_HELPER_SECURITY_DRIFT';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid='private.prelock_identity_relation_delete(bigint)'::regprocedure
      AND p.prosecdef
      AND 'search_path=pg_catalog, public, private'=ANY(p.proconfig)
  ) OR EXISTS (
    SELECT 1 FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
    WHERE p.oid='private.prelock_identity_relation_delete(bigint)'::regprocedure
      AND acl.grantee=0 AND acl.privilege_type='EXECUTE'
  ) OR has_function_privilege('anon','private.prelock_identity_relation_delete(bigint)','EXECUTE')
     OR has_function_privilege('authenticated','private.prelock_identity_relation_delete(bigint)','EXECUTE') THEN
    RAISE EXCEPTION 'IDENTITY_DELETE_PRELOCK_HELPER_SECURITY_DRIFT';
  END IF;
  v_definition := pg_get_functiondef('private.prelock_identity_relation_delete(bigint)'::regprocedure);
  IF v_definition ~ 'pg_advisory_xact_lock|guard_identity_mutation_snapshot'
     OR strpos(v_definition,'FOR UPDATE') < 1
     OR strpos(v_definition,'guard_transaction_id') <= strpos(v_definition,'FOR UPDATE')
     OR v_definition !~ 'IDENTITY_RELATION_DELETE_RETRY_REQUIRED' THEN
    RAISE EXCEPTION 'IDENTITY_DELETE_PRELOCK_ORDER_DRIFT';
  END IF;
  v_definition := pg_get_functiondef('private.guard_identity_mutation_snapshot()'::regprocedure);
  IF v_definition !~ 'guard_transaction_id = pg_catalog.pg_current_xact_id\(\)'
     OR v_definition !~ 'guard_backend_pid = pg_catalog.pg_backend_pid\(\)' THEN
    RAISE EXCEPTION 'IDENTITY_DELETE_GUARD_PROOF_WRITE_DRIFT';
  END IF;
  v_definition := pg_get_functiondef('private.prelock_identity_relation_update(jsonb,jsonb)'::regprocedure);
  v_lock_position := strpos(v_definition, 'pg_advisory_xact_lock(hashtext(''samme_som_mutation''))');
  v_people_position := strpos(v_definition, 'private.lock_identity_people');
  IF v_lock_position < 1 OR v_people_position <= v_lock_position THEN
    RAISE EXCEPTION 'IDENTITY_UPDATE_PRELOCK_ORDER_DRIFT';
  END IF;
  IF strpos(v_definition,'INSERT INTO private.identity_relation_update_prelock') <= v_people_position
     OR v_definition !~ 'pg_current_xact_id\(\)'
     OR v_definition !~ 'ORDER BY x' THEN
    RAISE EXCEPTION 'IDENTITY_UPDATE_PRELOCK_RECORD_ORDER_DRIFT';
  END IF;
  IF v_definition ~ 'app\.identity_relation_update_prelock' THEN
    RAISE EXCEPTION 'IDENTITY_UPDATE_PRELOCK_WRITABLE_MARKER_DRIFT';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f',p.proowner))) acl
    WHERE p.oid = 'private.lock_identity_people(bigint[])'::regprocedure
      AND acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
  )
     OR has_function_privilege('anon','private.lock_identity_people(bigint[])','EXECUTE')
     OR has_function_privilege('authenticated','private.lock_identity_people(bigint[])','EXECUTE') THEN
    RAISE EXCEPTION 'IDENTITY_LOCK_HELPER_ACL_DRIFT';
  END IF;
  v_definition := pg_get_functiondef('private.lock_identity_people(bigint[])'::regprocedure);
  IF v_definition !~ 'SELECT DISTINCT x FROM unnest\(p_person_ids\) x WHERE x IS NOT NULL'
     OR v_definition !~ 'ORDER BY p.id FOR UPDATE' THEN
    RAISE EXCEPTION 'IDENTITY_LOCK_HELPER_SORT_DEDUP_DRIFT';
  END IF;
  FOREACH v_writer IN ARRAY ARRAY[
    'public.red_samme_som(bigint,bigint)'::regprocedure,
    'public.red_ikke_samme_som(bigint,bigint)'::regprocedure,
    'public.red_slet_person(bigint)'::regprocedure
  ] LOOP
    v_definition := pg_get_functiondef(v_writer);
    v_lock_position := strpos(v_definition, 'pg_advisory_xact_lock(hashtext(''samme_som_mutation''))');
    v_people_position := strpos(v_definition, 'private.lock_identity_people');
    IF v_lock_position < 1 OR v_people_position <= v_lock_position THEN
      RAISE EXCEPTION 'IDENTITY_WRITER_LOCK_ORDER_DRIFT: %', v_writer;
    END IF;
  END LOOP;
  v_definition := pg_get_functiondef('public.enforce_samme_som_invariants()'::regprocedure);
  IF regexp_count(v_definition, 'private\.lock_identity_people') <> 1
     OR v_definition !~ 'IDENTITY_RELATION_UPDATE_PRELOCK_REQUIRED'
     OR v_definition !~ 'private\.identity_relation_update_prelock'
     OR v_definition !~ 'pg_catalog\.pg_current_xact_id\(\)'
     OR v_definition ~ 'pg_catalog\.pg_locks'
     OR v_definition ~ 'pg_catalog\.pg_advisory_unlock'
     OR v_definition ~ 'pg_catalog\.pg_try_advisory'
     OR v_definition ~ 'client_min_messages'
     OR v_definition ~ 'app\.identity_relation_update_prelock' THEN
    RAISE EXCEPTION 'IDENTITY_TRIGGER_LOCK_HELPER_DRIFT';
  END IF;
  v_definition := pg_get_functiondef('public._version_upsert_row(text,jsonb)'::regprocedure);
  IF strpos(v_definition,'private.prelock_identity_relation_update') < 1
     OR strpos(v_definition,'private.prelock_identity_relation_update') > strpos(v_definition,'UPDATE %1$I SET') THEN
    RAISE EXCEPTION 'IDENTITY_VERSION_UPSERT_PRELOCK_DRIFT';
  END IF;
  v_definition := pg_get_functiondef('public._delete_relation_evidence(bigint)'::regprocedure);
  IF strpos(v_definition,'private.prelock_identity_relation_delete') < 1
     OR strpos(v_definition,'private.prelock_identity_relation_delete') > strpos(v_definition,'DELETE FROM citation') THEN
    RAISE EXCEPTION 'IDENTITY_RAW_DELETE_HELPER_BYPASS';
  END IF;
  v_definition := regexp_replace(pg_get_functiondef('public.red_slet_relation(bigint)'::regprocedure),'\s+',' ','g');
  IF v_definition !~ 'SELECT rolle INTO v_role FROM relation WHERE id=p_relation_id'
     OR v_definition ~ 'SELECT rolle INTO v_role FROM relation WHERE id=p_relation_id FOR UPDATE'
     OR regexp_count(v_definition,'private\.prelock_identity_relation_delete') <> 2
     OR regexp_count(v_definition,'begin_change_set') <> 2
     OR v_definition !~ 'pg_advisory_xact_lock.*guard_identity_mutation_snapshot.*prelock_identity_relation_delete.*begin_change_set.*ELSE.*begin_change_set.*prelock_identity_relation_delete' THEN
    RAISE EXCEPTION 'IDENTITY_GENERIC_DELETE_LOCK_ORDER_DRIFT';
  END IF;
  v_definition := pg_get_functiondef('public._version_delete_row(text,jsonb)'::regprocedure);
  IF strpos(v_definition,'private.prelock_identity_relation_delete') < 1
     OR strpos(v_definition,'private.prelock_identity_relation_delete') > strpos(v_definition,'DELETE FROM %I') THEN
    RAISE EXCEPTION 'IDENTITY_VERSION_DELETE_HELPER_BYPASS';
  END IF;
  v_definition := pg_get_functiondef('public.red_fortryd_change_set(bigint,boolean)'::regprocedure);
  v_lock_position := strpos(v_definition,'pg_advisory_xact_lock(hashtext(''samme_som_mutation''))');
  IF v_lock_position < 1
     OR strpos(v_definition,'private.guard_identity_mutation_snapshot') <= v_lock_position
     OR v_definition !~ 'p_force OR CASE ce.op'
     OR strpos(v_definition,'set_config(''app.change_set_id''') <= strpos(v_definition,'private.guard_identity_mutation_snapshot')
     OR strpos(v_definition,'FOR ev IN SELECT') <= strpos(v_definition,'private.guard_identity_mutation_snapshot') THEN
    RAISE EXCEPTION 'IDENTITY_UNDO_PREANALYSIS_ORDER_DRIFT';
  END IF;
  RAISE NOTICE 'OK: C3 identitets-writers har fælles advisory/person-låsorden og privat xact-bevis';
END $verify$;

BEGIN;
DO $verify$
DECLARE
  v_actor uuid := '19390000-0000-4000-8000-000000000004';
  p_low bigint := -1939502101;
  p_high bigint := -1939502102;
  p_missing bigint := -1939502199;
BEGIN
  INSERT INTO auth.users(id,email)
  VALUES (v_actor,'c3-identity-lock-verify@test.invalid')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,email,rolle,navn)
  VALUES (v_actor,'c3-identity-lock-verify@test.invalid','redaktion','C3 identity lock verify')
  ON CONFLICT (id) DO UPDATE SET rolle='redaktion',navn='C3 identity lock verify';
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  INSERT INTO person(id,levende,koen) VALUES
    (p_low,false,'ukendt'),(p_high,false,'ukendt')
  ON CONFLICT (id) DO NOTHING;
  PERFORM private.lock_identity_people(ARRAY[p_high,p_low,p_low,NULL]);
  BEGIN
    PERFORM private.lock_identity_people(ARRAY[p_low,p_missing,NULL]);
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_PERSON_NOT_FOUND';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'IDENTITY_PERSON_NOT_FOUND' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claim.sub','19390000-0000-4000-8000-000000000098',true);
  BEGIN
    PERFORM private.lock_identity_people(ARRAY[p_low,p_high]);
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_LOCK_HELPER_ROLE_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%Kun redaktion%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: C3 sorteret person-lås accepterer negative fixtures og afviser manglende personer';
END $verify$;
ROLLBACK;

-- Task 2 UPDATE-bevis må komme fra den eksakte private transaktionsrække, ikke fra en
-- advisory-lås eller skrivbar GUC alene.
BEGIN;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM private.identity_relation_update_prelock) THEN
    RAISE EXCEPTION 'IDENTITY_VERIFY_PRELOCK_RECORD_RETAINED_FROM_PRIOR_RUN';
  END IF;
END $$;
DELETE FROM relation WHERE id IN (-1939502299,-1939502298,-1939502297);
DELETE FROM person WHERE id IN (-1939502201,-1939502202,-1939502203,-1939502204);
DELETE FROM profiles WHERE id='19390000-0000-4000-8000-000000000006';
DELETE FROM auth.users WHERE id='19390000-0000-4000-8000-000000000006';
COMMIT;

BEGIN;
DO $verify$
DECLARE v_actor uuid := '19390000-0000-4000-8000-000000000006';
BEGIN
  INSERT INTO auth.users(id,email) VALUES(v_actor,'c3-identity-prelock-verify@test.invalid')
    ON CONFLICT (id) DO UPDATE SET email=excluded.email;
  INSERT INTO profiles(id,email,rolle,navn)
    VALUES(v_actor,'c3-identity-prelock-verify@test.invalid','redaktion','C3 identity prelock verify')
    ON CONFLICT (id) DO UPDATE
      SET email=excluded.email,rolle=excluded.rolle,navn=excluded.navn;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  INSERT INTO person(id,levende,koen) VALUES
    (-1939502201,false,'ukendt'),(-1939502202,false,'ukendt'),
    (-1939502203,false,'ukendt'),(-1939502204,false,'ukendt')
    ON CONFLICT (id) DO UPDATE SET levende=excluded.levende,koen=excluded.koen;
  INSERT INTO relation(id,subjekt_type,subjekt_id,rolle,objekt_type,objekt_id) VALUES
    (-1939502299,'person',-1939502203,'bekendt_med','person',-1939502204),
    (-1939502298,'person',-1939502201,'samme_som','person',-1939502202),
    (-1939502297,'person',-1939502203,'ikke_samme_som','person',-1939502204);
END $verify$;
COMMIT;

BEGIN;
DO $verify$
DECLARE
  v_actor uuid := '19390000-0000-4000-8000-000000000006';
  v_current jsonb; v_target jsonb; v_has_lock boolean;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SELECT to_jsonb(r) || jsonb_build_object('rolle','ikke_samme_som')
    INTO v_target FROM relation r WHERE r.id=-1939502299;
  PERFORM set_config('app.identity_relation_update_prelock',jsonb_build_array(
    v_target->'id',v_target->'rolle',v_target->'subjekt_type',v_target->'subjekt_id',
    v_target->'objekt_type',v_target->'objekt_id')::text,true);
  BEGIN
    UPDATE relation SET rolle='ikke_samme_som' WHERE id=-1939502299;
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_SPOOF_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'IDENTITY_RELATION_UPDATE_PRELOCK_REQUIRED' THEN RAISE; END IF;
  END;
  PERFORM _version_upsert_row(
    'relation',
    (SELECT to_jsonb(r) || jsonb_build_object('periode_raw','generic undo remains supported')
     FROM relation r WHERE r.id=-1939502299)
  );
  IF (SELECT periode_raw FROM relation WHERE id=-1939502299)
     <> 'generic undo remains supported' THEN
    RAISE EXCEPTION 'IDENTITY_VERIFY_GENERIC_RELATION_UPSERT_REGRESSED';
  END IF;

  SELECT to_jsonb(r) INTO v_current FROM relation r WHERE r.id=-1939502297;
  v_target := v_current || jsonb_build_object('subjekt_id',-1939502201,'objekt_id',-1939502202);
  BEGIN
    PERFORM pg_advisory_lock(hashtext('samme_som_mutation'));
    BEGIN
      UPDATE relation SET subjekt_id=-1939502201,objekt_id=-1939502202 WHERE id=-1939502297;
      RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_SESSION_ONLY_REJECTION';
    EXCEPTION WHEN others THEN
      IF SQLERRM <> 'IDENTITY_RELATION_UPDATE_PRELOCK_REQUIRED' THEN RAISE; END IF;
    END;
    IF NOT pg_advisory_unlock(hashtext('samme_som_mutation')) THEN
      RAISE EXCEPTION 'IDENTITY_VERIFY_SESSION_LOCK_CLEANUP_FAILED';
    END IF;
  EXCEPTION WHEN others THEN
    PERFORM pg_advisory_unlock(hashtext('samme_som_mutation'));
    RAISE;
  END;
  SELECT EXISTS (
    SELECT 1 FROM pg_catalog.pg_locks l
    WHERE l.locktype='advisory' AND l.pid=pg_backend_pid() AND l.granted
      AND l.classid=(CASE WHEN hashtext('samme_som_mutation') < 0
                          THEN 4294967295::bigint ELSE 0::bigint END)::oid
      AND l.objid=(hashtext('samme_som_mutation')::bigint & 4294967295::bigint)::oid
      AND l.objsubid=1
  ) INTO v_has_lock;
  IF v_has_lock THEN RAISE EXCEPTION 'IDENTITY_VERIFY_SESSION_SCOPE_PROBE_LOCK_LEAKED'; END IF;
  BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('different_identity_mutation'));
    UPDATE relation SET rolle='ikke_samme_som' WHERE id=-1939502299;
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_DIFFERENT_KEY_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'IDENTITY_RELATION_UPDATE_PRELOCK_REQUIRED' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
    UPDATE relation SET objekt_id=-1939502296 WHERE id=-1939502297;
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_ADVISORY_ONLY_MISSING_TARGET_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'IDENTITY_RELATION_UPDATE_PRELOCK_REQUIRED' THEN RAISE; END IF;
  END;
  PERFORM set_config('app.identity_relation_update_prelock','',true);
  BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
    UPDATE relation SET subjekt_id=-1939502201,objekt_id=-1939502202 WHERE id=-1939502297;
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_ADVISORY_ONLY_COMPONENT_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'IDENTITY_RELATION_UPDATE_PRELOCK_REQUIRED' THEN RAISE; END IF;
  END;
  PERFORM set_config('app.identity_relation_update_prelock',jsonb_build_array(
    v_target->'id',v_target->'rolle',v_target->'subjekt_type',v_target->'subjekt_id',
    v_target->'objekt_type',v_target->'objekt_id')::text,true);
  BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
    UPDATE relation SET subjekt_id=-1939502201,objekt_id=-1939502202 WHERE id=-1939502297;
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_GUC_AND_ADVISORY_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'IDENTITY_RELATION_UPDATE_PRELOCK_REQUIRED' THEN RAISE; END IF;
  END;
  SELECT EXISTS (
    SELECT 1 FROM pg_catalog.pg_locks l
    WHERE l.locktype='advisory' AND l.pid=pg_backend_pid() AND l.granted
      AND l.mode='ExclusiveLock'
      AND l.classid=(CASE WHEN hashtext('samme_som_mutation') < 0
                          THEN 4294967295::bigint ELSE 0::bigint END)::oid
      AND l.objid=(hashtext('samme_som_mutation')::bigint & 4294967295::bigint)::oid
      AND l.objsubid=1
  ) INTO v_has_lock;
  IF v_has_lock THEN RAISE EXCEPTION 'IDENTITY_VERIFY_SUBTRANSACTION_LOCK_LEAKED'; END IF;
  BEGIN
    UPDATE relation SET subjekt_id=-1939502201,objekt_id=-1939502202 WHERE id=-1939502297;
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_REUSED_PROOF_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'IDENTITY_RELATION_UPDATE_PRELOCK_REQUIRED' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM private.prelock_identity_relation_update(v_current,v_target);
    UPDATE relation SET subjekt_id=-1939502201,objekt_id=-1939502202 WHERE id=-1939502297;
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_PRELOCKED_COMPONENT_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%IDENTITY_COMPONENT_CONTRADICTION%' THEN RAISE; END IF;
  END;
  IF EXISTS (
    SELECT 1 FROM private.identity_relation_update_prelock
    WHERE backend_pid=pg_backend_pid()
  ) THEN
    RAISE EXCEPTION 'IDENTITY_VERIFY_CAUGHT_ERROR_RETAINED_PRELOCK_RECORD';
  END IF;
  RAISE NOTICE 'OK: C3 identity UPDATE afviser advisory/GUC uden eksakt privat xact-bevis';
END $verify$;
ROLLBACK;

BEGIN;
DO $verify$
DECLARE
  v_actor uuid := '19390000-0000-4000-8000-000000000006';
  v_current jsonb; v_target_a jsonb; v_target_b jsonb; v_after jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SELECT to_jsonb(r) INTO v_current FROM relation r WHERE r.id=-1939502299;
  v_target_a := v_current || jsonb_build_object(
    'rolle','ikke_samme_som','subjekt_id',-1939502203,'objekt_id',-1939502201
  );
  v_target_b := v_current || jsonb_build_object(
    'rolle','ikke_samme_som','subjekt_id',-1939502204,'objekt_id',-1939502201
  );
  PERFORM private.prelock_identity_relation_update(v_current,v_target_a);
  IF NOT EXISTS (
    SELECT 1 FROM private.identity_relation_update_prelock p
    WHERE p.transaction_id=pg_current_xact_id()
      AND p.backend_pid=pg_backend_pid()
      AND p.relation_id=-1939502299
      AND p.current_signature=jsonb_build_array(
        -1939502299,'bekendt_med','person',-1939502203,'person',-1939502204
      )
      AND p.target_signature=jsonb_build_array(
        -1939502299,'ikke_samme_som','person',-1939502203,'person',-1939502201
      )
      AND p.locked_person_ids=ARRAY[-1939502204,-1939502203,-1939502201]::bigint[]
  ) THEN
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXACT_PRELOCK_RECORD_MISSING';
  END IF;
  BEGIN
    UPDATE relation
      SET rolle='ikke_samme_som',subjekt_id=-1939502204,objekt_id=-1939502201
      WHERE id=-1939502299;
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_TARGET_MISMATCH_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'IDENTITY_RELATION_UPDATE_PRELOCK_REQUIRED' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE relation SET subjekt_id=-1939502201,objekt_id=-1939502202
      WHERE id=-1939502297;
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_RELATION_MISMATCH_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'IDENTITY_RELATION_UPDATE_PRELOCK_REQUIRED' THEN RAISE; END IF;
  END;
  PERFORM private.prelock_identity_relation_update(v_current,v_target_b);
  IF (SELECT count(*) FROM private.identity_relation_update_prelock
      WHERE transaction_id=pg_current_xact_id() AND backend_pid=pg_backend_pid()) <> 1
     OR NOT EXISTS (
       SELECT 1 FROM private.identity_relation_update_prelock p
       WHERE p.transaction_id=pg_current_xact_id()
         AND p.backend_pid=pg_backend_pid()
         AND p.relation_id=-1939502299
         AND p.target_signature=jsonb_build_array(
           -1939502299,'ikke_samme_som','person',-1939502204,'person',-1939502201
         )
     ) THEN
    RAISE EXCEPTION 'IDENTITY_VERIFY_REPRELOCK_RETAINED_OBSOLETE_RECORD';
  END IF;
  UPDATE relation
    SET rolle='ikke_samme_som',subjekt_id=-1939502204,objekt_id=-1939502201
    WHERE id=-1939502299;
  BEGIN
    UPDATE relation SET periode_raw='must prelock again' WHERE id=-1939502299;
    RAISE EXCEPTION 'IDENTITY_VERIFY_EXPECTED_OBSOLETE_SIGNATURE_REUSE_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'IDENTITY_RELATION_UPDATE_PRELOCK_REQUIRED' THEN RAISE; END IF;
  END;
  SELECT to_jsonb(r) INTO v_after FROM relation r WHERE r.id=-1939502299;
  PERFORM private.prelock_identity_relation_update(
    v_after,v_after || jsonb_build_object('periode_raw','fresh exact prelock')
  );
  UPDATE relation SET periode_raw='fresh exact prelock' WHERE id=-1939502299;
END $verify$;
ROLLBACK;

DO $verify$
BEGIN
  IF EXISTS (SELECT 1 FROM private.identity_relation_update_prelock) THEN
    RAISE EXCEPTION 'IDENTITY_VERIFY_ROLLBACK_RETAINED_PRELOCK_RECORD';
  END IF;
END $verify$;

BEGIN;
DO $verify$
DECLARE
  v_actor uuid := '19390000-0000-4000-8000-000000000006';
  v_current jsonb; v_target jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SELECT to_jsonb(r) INTO v_current FROM relation r WHERE r.id=-1939502299;
  v_target := v_current || jsonb_build_object(
    'rolle','ikke_samme_som','subjekt_id',-1939502204,'objekt_id',-1939502201
  );
  PERFORM private.prelock_identity_relation_update(v_current,v_target);
  UPDATE relation
    SET rolle='ikke_samme_som',subjekt_id=-1939502204,objekt_id=-1939502201
    WHERE id=-1939502299;
  IF (SELECT count(*) FROM private.identity_relation_update_prelock
      WHERE transaction_id=pg_current_xact_id() AND backend_pid=pg_backend_pid()) <> 1 THEN
    RAISE EXCEPTION 'IDENTITY_VERIFY_SUCCESS_LOST_PRELOCK_RECORD_EARLY';
  END IF;
END $verify$;
COMMIT;

BEGIN;
DO $verify$
DECLARE
  v_actor uuid := '19390000-0000-4000-8000-000000000006';
  v_current jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM private.identity_relation_update_prelock) THEN
    RAISE EXCEPTION 'IDENTITY_VERIFY_SUCCESS_COMMIT_RETAINED_PRELOCK_RECORD';
  END IF;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SELECT to_jsonb(r) INTO v_current FROM relation r WHERE r.id=-1939502299;
  PERFORM private.prelock_identity_relation_update(
    v_current,v_current || jsonb_build_object('periode_raw','unused prelock')
  );
END $verify$;
COMMIT;

DO $verify$
BEGIN
  IF EXISTS (SELECT 1 FROM private.identity_relation_update_prelock) THEN
    RAISE EXCEPTION 'IDENTITY_VERIFY_UNUSED_COMMIT_RETAINED_PRELOCK_RECORD';
  END IF;
  RAISE NOTICE 'OK: C3 eksakt xact/relation/endepunkt-prelock har deterministisk rollback/error/commit/genkørsels-livscyklus';
END $verify$;

BEGIN;
DELETE FROM relation WHERE id IN (-1939502299,-1939502298,-1939502297);
DELETE FROM person WHERE id IN (-1939502201,-1939502202,-1939502203,-1939502204);
DELETE FROM profiles WHERE id='19390000-0000-4000-8000-000000000006';
DELETE FROM auth.users WHERE id='19390000-0000-4000-8000-000000000006';
COMMIT;

SELECT to_regclass('public.profiles') IS NOT NULL AS profiles_ok,
       to_regclass('public.suggestion') IS NOT NULL AS suggestion_ok;
-- Forvent profiles_ok=t, suggestion_ok=t

DO $$ BEGIN
  BEGIN
    INSERT INTO profiles(id, rolle) VALUES (gen_random_uuid(), 'forsker');
    RAISE EXCEPTION 'CHECK fejlede ikke — forventede afvisning';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK: rolle-CHECK afviser forsker';
  END;
END $$;

-- =============================================================
-- 2026-08-03: Task 15 — publicerede kilde-record-versioner
-- Den offentlige read-flade må kun udlevere en opaque record_ref og aldrig
-- private source_record-id'er. Uforbundne legacy-narrativer bevares særskilt.
-- =============================================================
DO $$
DECLARE
  v_person bigint := -987651001;
  v_source bigint := -987651002;
  v_run uuid := '11111111-1111-1111-1111-111111111151';
  v_record uuid := '22222222-2222-2222-2222-222222222251';
  -- Separate record for the insert-path assertion below: narrative_record_publication_active_record_uidx
  -- (C3 fund B4) now allows only one active (draft/published) binding per source_record_id, so the
  -- "new-publication path" case can no longer reuse v_record once it already carries v_binding.
  v_record2 uuid := '22222222-2222-2222-2222-222222222252';
  v_bound_narrative bigint := -987651003;
  v_legacy_narrative bigint := -987651004;
  v_insert_narrative bigint := -987651005;
  v_actor uuid := '11111111-1111-4111-8111-111111111152';
  v_binding uuid;
  v_published_binding uuid;
  v_rows jsonb;
BEGIN
  IF to_regclass('private.narrative_record_publication') IS NULL
     OR to_regprocedure('public.public_person_bio_source_versions(bigint[])') IS NULL THEN
    RAISE EXCEPTION 'FEJL: Task 15 publiceringsbinding eller read-RPC mangler';
  END IF;
  IF has_table_privilege('anon','private.narrative_record_publication','SELECT')
     OR has_table_privilege('authenticated','private.narrative_record_publication','SELECT')
     OR has_function_privilege('anon','red_publicer_narrative_record(bigint,uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'FEJL: Task 15 åbner privat binding eller redaktionsmutation';
  END IF;

  BEGIN
    INSERT INTO auth.users(id,email) VALUES (v_actor,'record-publication-verify@test.invalid');
    INSERT INTO profiles(id,rolle,email) VALUES (v_actor,'redaktion','record-publication-verify@test.invalid');
    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    INSERT INTO person(id,levende,privat,staged,visning_navn)
      VALUES (v_person,false,false,false,'VERIFY record-version');
    INSERT INTO source(id,slags,titel,udgave,aar)
      VALUES (v_source,'DAA-udgave','VERIFY Aarbogen','VERIFY 2026',2026);
    INSERT INTO private.extraction_run(
      id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest
    ) VALUES (v_run,v_source,'task15-verify','1','verify','verify',repeat('1',64),'{}');
    INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
      VALUES (v_record,v_source,'verify-record','person_entry',v_run);
    INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
      VALUES (v_record2,v_source,'verify-record-2','person_entry',v_run);
    INSERT INTO narrative(id,subjekt_type,subjekt_id,source_id,tekst,privat) VALUES
      (v_bound_narrative,'person',v_person,v_source,'Bundet record-tekst',false),
      (v_legacy_narrative,'person',v_person,v_source,'Legacy-tekst',false),
      (v_insert_narrative,'person',v_person,v_source,'Ny record-tekst',false);
    INSERT INTO private.narrative_record_publication(
      narrative_id,source_record_id,record_label,citation_label,status
    ) VALUES (
      v_bound_narrative,v_record,'Linje I, nr. 1','s. 1','draft'
    ) RETURNING id INTO v_binding;

    IF public.narrative_record_contract_version()=2 THEN
      BEGIN
        PERFORM red_publicer_narrative_record(
          v_bound_narrative,v_record,'Linje I, nr. 1','s. 1'
        );
        RAISE EXCEPTION 'FEJL: Task 15 legacy-writer accepteret ved version 2';
      EXCEPTION WHEN others THEN
        IF SQLERRM='FEJL: Task 15 legacy-writer accepteret ved version 2' THEN RAISE; END IF;
        IF SQLERRM<>'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED' THEN
          RAISE EXCEPTION 'FEJL: Task 15 legacy-writer gav forkert v2-fejl: %',SQLERRM;
        END IF;
      END;
      IF (SELECT status FROM private.narrative_record_publication WHERE id=v_binding)
           IS DISTINCT FROM 'draft'
         OR EXISTS (SELECT 1 FROM private.narrative_publication_event
                     WHERE binding_id=v_binding) THEN
        RAISE EXCEPTION 'FEJL: Task 15 legacy-writer skrev ved version 2';
      END IF;
      RAISE NOTICE 'OK: Task 15 legacy-writer er fail-closed ved version 2';
      RAISE EXCEPTION 'ROLLBACK_TASK15_TESTDATA';
    END IF;

    BEGIN
      PERFORM red_publicer_narrative_record(
        v_bound_narrative,v_record,'Forkert label','s. 1'
      );
      RAISE EXCEPTION 'FEJL: Task 15 accepterede drift i en eksisterende draft-binding';
    EXCEPTION WHEN others THEN
      IF SQLERRM='FEJL: Task 15 accepterede drift i en eksisterende draft-binding' THEN RAISE; END IF;
      IF SQLERRM<>'SOURCE_RECORD_PUBLICATION_BINDING_MISMATCH' THEN
        RAISE EXCEPTION 'FEJL: Task 15 draft-drift gav forkert fejl: %',SQLERRM;
      END IF;
    END;
    IF (SELECT status FROM private.narrative_record_publication WHERE id=v_binding) IS DISTINCT FROM 'draft'
       OR (SELECT published_at FROM private.narrative_record_publication WHERE id=v_binding) IS NOT NULL THEN
      RAISE EXCEPTION 'FEJL: Task 15 muterede draft ved mismatch';
    END IF;

    SELECT red_publicer_narrative_record(
      v_bound_narrative,v_record,'Linje I, nr. 1','s. 1'
    ) INTO v_published_binding;
    IF v_published_binding IS DISTINCT FROM v_binding
       OR (SELECT status FROM private.narrative_record_publication WHERE id=v_binding) IS DISTINCT FROM 'published'
       OR (SELECT published_at FROM private.narrative_record_publication WHERE id=v_binding) IS NULL THEN
      RAISE EXCEPTION 'FEJL: Task 15 publicerer ikke en eksakt eksisterende draft-binding';
    END IF;

    SELECT red_publicer_narrative_record(
      v_insert_narrative,v_record2,'Linje I, nr. 2','s. 2'
    ) INTO v_published_binding;
    IF NOT EXISTS (
      SELECT 1 FROM private.narrative_record_publication
       WHERE id=v_published_binding AND narrative_id=v_insert_narrative
         AND source_record_id=v_record2 AND record_label='Linje I, nr. 2'
         AND citation_label='s. 2' AND status='published' AND published_at IS NOT NULL
    ) THEN
      RAISE EXCEPTION 'FEJL: Task 15 bevarer ikke ny-publiceringsvejen';
    END IF;

    SELECT jsonb_agg(to_jsonb(row) ORDER BY row.provenance_kind,row.record_label)
      INTO v_rows
      FROM public.public_person_bio_source_versions(ARRAY[v_person]) AS row;
    IF jsonb_array_length(v_rows) <> 3 THEN
      RAISE EXCEPTION 'FEJL: Task 15 returnerede ikke begge publicerede records og legacy-narrativ';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_rows) value
       WHERE value->>'provenance_kind'='source_record'
         AND nullif(value->>'record_ref','') IS NOT NULL
         AND value->>'narrative_text'='Bundet record-tekst'
    ) THEN
      RAISE EXCEPTION 'FEJL: Task 15 mangler publiceret source_record-projektion';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_rows) value
       WHERE value->>'provenance_kind'='legacy_narrative'
         AND value->>'record_ref' IS NULL
         AND value->>'narrative_text'='Legacy-tekst'
    ) THEN
      RAISE EXCEPTION 'FEJL: Task 15 bevarer ikke legacy-narrativ separat';
    END IF;
    IF EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_rows) value
       WHERE value ? 'source_record_id' OR value ? 'source_persona_id'
          OR value ? 'raw_text' OR value ? 'score'
    ) THEN
      RAISE EXCEPTION 'FEJL: Task 15 lækker privat record-/reviewdata';
    END IF;
    RAISE NOTICE 'OK: Task 15 publicerer record-version og legacy-narrativ uden private felter';
    RAISE EXCEPTION 'ROLLBACK_TASK15_TESTDATA';
  EXCEPTION WHEN others THEN
    IF SQLERRM='ROLLBACK_TASK15_TESTDATA' THEN
      RAISE NOTICE 'OK: Task 15-testdata rullet tilbage';
    ELSE
      RAISE;
    END IF;
  END;
END $$;

-- ===== Evidensimport Fase 2 / Task 4: privat append-only kildelag =====
-- Selvstændig fixture. Den beviser katalog, kilde-isolation, event-versionering,
-- append-only-adfærd og rettigheder og ruller altid sine data tilbage.
DO $evidence_verify$
DECLARE
  v_required text[] := ARRAY[
    'extraction_run','source_rendition','source_record',
    'source_record_occurrence','source_record_anchor_event',
    'source_record_revision_event','source_observation',
    'source_observation_text','source_mention','source_persona',
    'source_persona_mention'
  ];
  v_missing text[];
  v_actor uuid := '10000000-0000-0000-0000-000000000001';
  v_run_a uuid := '20000000-0000-0000-0000-000000000001';
  v_run_b uuid := '20000000-0000-0000-0000-000000000002';
  v_rendition_a uuid := '30000000-0000-0000-0000-000000000001';
  v_rendition_b uuid := '30000000-0000-0000-0000-000000000002';
  v_record_a uuid := '40000000-0000-0000-0000-000000000001';
  v_record_b uuid := '40000000-0000-0000-0000-000000000002';
  v_record_c uuid := '40000000-0000-0000-0000-000000000004';
  v_record_foreign uuid := '40000000-0000-0000-0000-000000000003';
  v_occurrence uuid := '50000000-0000-0000-0000-000000000001';
  v_observation uuid := '60000000-0000-0000-0000-000000000001';
  v_mention uuid := '70000000-0000-0000-0000-000000000001';
  v_persona uuid := '80000000-0000-0000-0000-000000000001';
  v_persona_foreign uuid := '80000000-0000-0000-0000-000000000002';
  v_error text;
BEGIN
  SELECT array_agg(required_name ORDER BY required_name)
    INTO v_missing
    FROM unnest(v_required) AS required_name
   WHERE to_regclass(format('private.%I', required_name)) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: evidenslag mangler tabeller: %', v_missing;
  END IF;

  IF EXISTS (
    SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='private'
       AND c.relname=ANY(v_required)
       AND NOT c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'FEJL: mindst én privat evidenstabel mangler RLS';
  END IF;
  IF EXISTS (
    SELECT 1
      FROM unnest(v_required) required_name
     WHERE NOT EXISTS (
       SELECT 1 FROM pg_trigger t
        WHERE t.tgrelid=format('private.%I',required_name)::regclass
          AND NOT t.tgisinternal AND t.tgenabled<>'D'
          AND (t.tgtype & 1)<>0 AND (t.tgtype & 2)<>0
          AND (t.tgtype & 8)<>0 AND (t.tgtype & 16)<>0
     )
        OR NOT EXISTS (
       SELECT 1 FROM pg_trigger t
        WHERE t.tgrelid=format('private.%I',required_name)::regclass
          AND NOT t.tgisinternal AND t.tgenabled<>'D'
          AND (t.tgtype & 1)=0 AND (t.tgtype & 2)<>0 AND (t.tgtype & 32)<>0
     )
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_APPEND_ONLY_TRIGGER_CONTRACT_DRIFT';
  END IF;
  IF has_schema_privilege('anon','private','USAGE')
     OR has_schema_privilege('authenticated','private','USAGE') THEN
    RAISE EXCEPTION 'FEJL: anon/authenticated har USAGE på private';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(v_required) AS required_name
     WHERE has_table_privilege('anon',format('private.%I',required_name),'SELECT')
        OR has_table_privilege('authenticated',format('private.%I',required_name),'SELECT')
        OR has_table_privilege('authenticated',format('private.%I',required_name),'INSERT')
  ) THEN
    RAISE EXCEPTION 'FEJL: privat evidenstabel har direkte anon/authenticated-rettighed';
  END IF;

  BEGIN
    INSERT INTO auth.users(id,email) VALUES (v_actor,'evidence-verify@test.invalid');
    INSERT INTO source(id,titel,import_key) VALUES
      (-987650001,'Evidens verify A','verify:evidence:a'),
      (-987650002,'Evidens verify B','verify:evidence:b');
    INSERT INTO private.extraction_run(
      id,source_id,run_key,schema_version,extractor_version,profile_version,
      input_sha256,manifest
    ) VALUES
      (v_run_a,-987650001,'run-a','1.0','verify','verify',repeat('a',64),'{}'),
      (v_run_b,-987650002,'run-b','1.0','verify','verify',repeat('b',64),'{}');
    INSERT INTO private.source_rendition(
      id,source_id,rendition_key,rendition_kind,content_sha256,metadata
    ) VALUES
      (v_rendition_a,-987650001,'rendition-a','text_layer',repeat('c',64),'{}'),
      (v_rendition_b,-987650002,'rendition-b','text_layer',repeat('d',64),'{}');
    INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
      VALUES
      (v_record_a,-987650001,'record-a','person_entry',v_run_a),
      (v_record_b,-987650001,'record-b','person_entry',v_run_a),
      (v_record_c,-987650001,'record-c','person_entry',v_run_a),
      (v_record_foreign,-987650002,'record-foreign','person_entry',v_run_b);
    INSERT INTO private.source_record_occurrence(
      id,rendition_id,occurrence_key,page_from,page_to,column_label,
      char_from,char_to,bbox,verbatim_text,physical_fingerprint,
      structural_fingerprint,extraction_run_id
    ) VALUES (
      v_occurrence,v_rendition_a,'occurrence-a',1,1,NULL,0,12,NULL,
      'Anna Reventl','physical-a','structural-a',v_run_a
    );

    IF EXISTS (
      SELECT 1 FROM private.source_record_anchor_event
       WHERE occurrence_id=v_occurrence
    ) THEN
      RAISE EXCEPTION 'FEJL: occurrence kan ikke stå uforankret';
    END IF;

    INSERT INTO private.source_observation(
      id,occurrence_id,observation_kind,page_from,page_to,column_label,
      char_from,char_to,bbox,verbatim_text,quality_status,
      extraction_method,extraction_run_id
    ) VALUES (
      v_observation,v_occurrence,'name_clause',1,1,NULL,0,12,NULL,
      'Anna Reventl','clear','verify',v_run_a
    );
    INSERT INTO private.source_observation_text(
      id,observation_id,rendition_id,version,verbatim_text,char_from,char_to,
      bbox,is_preferred,created_by
    ) VALUES (
      '61000000-0000-0000-0000-000000000001',v_observation,v_rendition_a,
      1,'Anna Reventl',0,12,NULL,true,v_actor
    );
    INSERT INTO private.source_mention(
      id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id
    ) VALUES (v_mention,v_observation,'person',0,4,'Anna',v_run_a);
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
      VALUES
      (v_persona,-987650001,'persona-a',v_run_a),
      (v_persona_foreign,-987650002,'persona-b',v_run_b);
    INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
      VALUES (v_persona,v_mention,'principal',1);

    v_error := NULL;
    BEGIN
      INSERT INTO private.source_mention(
        id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id
      ) VALUES (
        '70000000-0000-0000-0000-000000000002',v_observation,'person',0,99,
        'udenfor',v_run_a
      );
    EXCEPTION WHEN others THEN v_error := SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_MENTION_SPAN_INVALID%' THEN
      RAISE EXCEPTION 'FEJL: mention uden for observation blev ikke afvist korrekt: %',v_error;
    END IF;

    v_error := NULL;
    BEGIN
      INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
        VALUES (v_persona_foreign,v_mention,'principal',1);
    EXCEPTION WHEN others THEN v_error := SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_SOURCE_MISMATCH%' THEN
      RAISE EXCEPTION 'FEJL: persona kunne samle mentions på tværs af kilder: %',v_error;
    END IF;

    v_error := NULL;
    BEGIN
      INSERT INTO private.source_record_anchor_event(
        id,occurrence_id,source_record_id,decision_status,evidence,version
      ) VALUES (
        '90000000-0000-0000-0000-000000000001',v_occurrence,v_record_a,
        'accepted','{}',1
      );
    EXCEPTION WHEN others THEN v_error := SQLERRM; END;
    IF v_error IS NULL THEN
      RAISE EXCEPTION 'FEJL: accepted anchor uden actor/evidence blev accepteret';
    END IF;

    INSERT INTO private.source_record_anchor_event(
      id,occurrence_id,source_record_id,decision_status,evidence,version,
      decided_by,decided_by_name
    ) VALUES (
      '90000000-0000-0000-0000-000000000002',v_occurrence,v_record_a,
      'accepted','{"basis":"verify"}',1,v_actor,'Verify'
    );
    v_error := NULL;
    BEGIN
      INSERT INTO private.source_record_anchor_event(
        id,occurrence_id,source_record_id,decision_status,evidence,version,
        decided_by,decided_by_name
      ) VALUES (
        '90000000-0000-0000-0000-000000000003',v_occurrence,v_record_b,
        'accepted','{"basis":"verify"}',1,v_actor,'Verify'
      );
    EXCEPTION WHEN others THEN v_error := SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_ANCHOR_CONFLICT%' THEN
      RAISE EXCEPTION 'FEJL: to aktuelle accepted anchors blev ikke afvist korrekt: %',v_error;
    END IF;

    INSERT INTO private.source_record_anchor_event(
      id,occurrence_id,source_record_id,decision_status,evidence,version,
      decided_by,decided_by_name
    ) VALUES
      ('90000000-0000-0000-0000-000000000004',v_occurrence,v_record_a,
       'rejected','{"basis":"review"}',2,v_actor,'Verify'),
      ('90000000-0000-0000-0000-000000000005',v_occurrence,v_record_a,
       'proposed','{"basis":"new evidence"}',3,NULL,NULL),
      ('90000000-0000-0000-0000-000000000006',v_occurrence,v_record_b,
       'accepted','{"basis":"review"}',1,v_actor,'Verify');
    IF NOT EXISTS (
      SELECT 1 FROM private.source_record_anchor_current
       WHERE occurrence_id=v_occurrence AND source_record_id=v_record_b
         AND decision_status='accepted'
    ) THEN
      RAISE EXCEPTION 'FEJL: current anchor-view udleder ikke seneste accepted event';
    END IF;

    v_error := NULL;
    BEGIN
      INSERT INTO private.source_record_anchor_event(
        id,occurrence_id,source_record_id,decision_status,evidence,version
      ) VALUES (
        '90000000-0000-0000-0000-000000000007',v_occurrence,v_record_foreign,
        'proposed','{"basis":"wrong source"}',1
      );
    EXCEPTION WHEN others THEN v_error := SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_SOURCE_MISMATCH%' THEN
      RAISE EXCEPTION 'FEJL: anchor på tværs af kilder blev ikke afvist korrekt: %',v_error;
    END IF;

    INSERT INTO private.source_record_revision_event(
      id,predecessor_record_id,successor_record_id,relation_kind,
      decision_status,evidence,version
    ) VALUES (
      'a0000000-0000-0000-0000-000000000001',v_record_a,v_record_b,
      'split_into','proposed','{"basis":"verify"}',1
    );
    INSERT INTO private.source_record_revision_event(
      id,predecessor_record_id,successor_record_id,relation_kind,
      decision_status,evidence,version,decided_by,decided_by_name
    ) VALUES
      ('a0000000-0000-0000-0000-000000000002',v_record_a,v_record_b,
       'split_into','rejected','{"basis":"review"}',2,v_actor,'Verify'),
      ('a0000000-0000-0000-0000-000000000003',v_record_a,v_record_b,
       'split_into','proposed','{"basis":"new evidence"}',3,NULL,NULL);
    IF NOT EXISTS (
      SELECT 1 FROM private.source_record_revision_current
       WHERE predecessor_record_id=v_record_a AND successor_record_id=v_record_b
         AND relation_kind='split_into' AND decision_status='proposed' AND version=3
    ) THEN
      RAISE EXCEPTION 'FEJL: afvist revision kan ikke genforeslås append-only';
    END IF;
    v_error:=NULL;
    BEGIN
      INSERT INTO private.source_record_revision_event(
        id,predecessor_record_id,successor_record_id,relation_kind,
        decision_status,evidence,version,decided_by,decided_by_name
      ) VALUES (
        'a0000000-0000-0000-0000-000000000004',v_record_a,v_record_b,
        'split_into','accepted','{"basis":"invalid reused successor"}',4,v_actor,'Verify'
      );
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    IF v_error IS NULL OR v_error NOT LIKE 'EVIDENCE_REVISION_SUCCESSOR_ALREADY_ANCHORED%' THEN
      RAISE EXCEPTION 'FEJL: accepted revision genbrugte tavst en forankret successor: %',v_error;
    END IF;
    INSERT INTO private.source_record_revision_event(
      id,predecessor_record_id,successor_record_id,relation_kind,
      decision_status,evidence,version,decided_by,decided_by_name
    ) VALUES (
      'a0000000-0000-0000-0000-000000000005',v_record_a,v_record_c,
      'split_into','accepted','{"basis":"fresh successor"}',1,v_actor,'Verify'
    );
    -- En reanchor er eksplicit append-only: først afløses den gamle anchor,
    -- derefter accepteres den friske, reviewed successor.
    INSERT INTO private.source_record_anchor_event(
      id,occurrence_id,source_record_id,decision_status,evidence,version,
      decided_by,decided_by_name
    ) VALUES
      ('90000000-0000-0000-0000-000000000008',v_occurrence,v_record_b,
       'rejected','{"basis":"explicit reanchor"}',2,v_actor,'Verify'),
      ('90000000-0000-0000-0000-000000000009',v_occurrence,v_record_c,
       'accepted','{"basis":"accepted split successor"}',1,v_actor,'Verify');
    IF NOT EXISTS (
      SELECT 1 FROM private.source_record_anchor_current
       WHERE occurrence_id=v_occurrence AND source_record_id=v_record_c
         AND decision_status='accepted'
    ) OR EXISTS (
      SELECT 1 FROM private.source_record_anchor_current
       WHERE occurrence_id=v_occurrence AND source_record_id=v_record_b
         AND decision_status='accepted'
    ) THEN
      RAISE EXCEPTION 'FEJL: accepted split successor krævede ikke eksplicit reanchor';
    END IF;

    v_error := NULL;
    BEGIN
      UPDATE private.source_observation SET quality_status='uncertain'
       WHERE id=v_observation;
    EXCEPTION WHEN others THEN v_error := SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_APPEND_ONLY%' THEN
      RAISE EXCEPTION 'FEJL: rå observation kunne opdateres: %',v_error;
    END IF;
    v_error := NULL;
    BEGIN
      DELETE FROM private.source_record WHERE id=v_record_a;
    EXCEPTION WHEN others THEN v_error := SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_APPEND_ONLY%' THEN
      RAISE EXCEPTION 'FEJL: source record kunne slettes: %',v_error;
    END IF;
    v_error := NULL;
    BEGIN
      TRUNCATE private.source_persona_mention;
    EXCEPTION WHEN others THEN v_error := SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_APPEND_ONLY%' THEN
      RAISE EXCEPTION 'FEJL: rå persona-mention kunne truncates: %',v_error;
    END IF;
    INSERT INTO private.source_mention(
      id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id
    ) VALUES (
      '70000000-0000-0000-0000-000000000003',v_observation,'person',5,12,'Reventl',v_run_a
    );
    INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
      VALUES (v_persona,'70000000-0000-0000-0000-000000000003','secondary',2);

    DELETE FROM auth.users WHERE id=v_actor;
    IF NOT EXISTS (
      SELECT 1 FROM private.source_record_anchor_event
       WHERE occurrence_id=v_occurrence AND decision_status='accepted'
         AND decided_by=v_actor AND decided_by_name='Verify'
    ) THEN
      RAISE EXCEPTION 'FEJL: actorsletning bevarede ikke uforanderligt audit-id og navn';
    END IF;

    EXECUTE 'CREATE TABLE private._evidence_default_priv_verify(id integer)';
    IF has_table_privilege('anon','private._evidence_default_priv_verify','SELECT')
       OR has_table_privilege('authenticated','private._evidence_default_priv_verify','SELECT')
       OR has_table_privilege('authenticated','private._evidence_default_priv_verify','INSERT') THEN
      RAISE EXCEPTION 'FEJL: default privileges eksponerer et senere private-objekt';
    END IF;
    EXECUTE $sql$CREATE FUNCTION private._evidence_default_priv_verify()
      RETURNS integer LANGUAGE sql AS 'SELECT 1'$sql$;
    v_error := NULL;
    BEGIN
      SET LOCAL ROLE anon;
      PERFORM private._evidence_default_priv_verify();
      RESET ROLE;
    EXCEPTION WHEN insufficient_privilege THEN v_error := SQLERRM; END;
    IF v_error IS NULL THEN
      RAISE EXCEPTION 'FEJL: anon kan kalde en senere private-funktion';
    END IF;
    v_error := NULL;
    BEGIN
      SET LOCAL ROLE authenticated;
      PERFORM private._evidence_default_priv_verify();
      RESET ROLE;
    EXCEPTION WHEN insufficient_privilege THEN v_error := SQLERRM; END;
    IF v_error IS NULL THEN
      RAISE EXCEPTION 'FEJL: authenticated kan kalde en senere private-funktion';
    END IF;
    EXECUTE 'DROP FUNCTION private._evidence_default_priv_verify()';
    EXECUTE 'DROP TABLE private._evidence_default_priv_verify';

    RAISE EXCEPTION 'ROLLBACK_EVIDENCE_VERIFY';
  EXCEPTION WHEN others THEN
    IF SQLERRM='ROLLBACK_EVIDENCE_VERIFY' THEN
      RAISE NOTICE 'OK: privat append-only evidenslag — katalog, provenance, events, immutabilitet og ACL';
    ELSE
      RAISE;
    END IF;
  END;
END $evidence_verify$;

-- #166 149b (M-5): private.reimport_event må have præcis én CHECK på operation, og
-- den skal kende legacy_migration. Fanger både en glemt migration og en gendannet
-- gammel constraint fra den omdøbte reimport_1939_write_event-sti. Assert'en fandtes
-- kun i tests/sql/test-reimport-writer-migration.sql, som alene dækker CI's
-- præ-153-migrerede sti; db-verify.sql er prod-siden.
DO $reimport_event_operation_check_verify$
DECLARE v_count integer; v_definition text;
BEGIN
  SELECT count(*),min(pg_get_constraintdef(oid))
    INTO v_count,v_definition
    FROM pg_constraint
   WHERE conrelid='private.reimport_event'::regclass
     AND contype='c'
     AND pg_get_constraintdef(oid) LIKE '%operation%';
  IF v_count<>1 OR v_definition NOT LIKE '%legacy_migration%' OR v_definition NOT LIKE '%clause_evidence%' THEN
    RAISE EXCEPTION 'REIMPORT_EVENT_OPERATION_CHECK_DRIFT';
  END IF;
  RAISE NOTICE 'OK: private.reimport_event operation-CHECK er entydig og kender legacy_migration';
END
$reimport_event_operation_check_verify$;

-- #148 4.1a: klausullagets skema er til stede, vokabularet er lukket, og
-- legacy-writeren tæller kun helpostens mentions.
DO $clause_schema_verify$
DECLARE v_def text; v_count integer; v_rel text; v_role text;
BEGIN
  IF to_regclass('private.vocab') IS NULL OR to_regclass('private.clause_disposition') IS NULL
     OR to_regclass('private.clause_disposition_current') IS NULL THEN
    RAISE EXCEPTION 'CLAUSE_SCHEMA_OBJECTS_MISSING';
  END IF;
  SELECT count(*) INTO v_count FROM information_schema.columns
   WHERE table_schema='private' AND table_name='source_observation'
     AND column_name IN ('parent_observation_id','clause_ordinal','clause_classification','clause_flags','post_char_from','post_char_to');
  IF v_count<>6 THEN RAISE EXCEPTION 'CLAUSE_SCHEMA_COLUMNS_MISSING: %', v_count; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.source_observation'::regclass AND tgname='trg_source_observation_clause')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.clause_disposition'::regclass AND tgname='trg_clause_disposition_validate') THEN
    RAISE EXCEPTION 'CLAUSE_SCHEMA_TRIGGER_MISSING';
  END IF;
  SELECT count(*) INTO v_count FROM private.source_observation ob
   WHERE NOT EXISTS (SELECT 1 FROM private.vocab v WHERE v.scheme='observation_kind' AND v.code=ob.observation_kind);
  IF v_count<>0 THEN RAISE EXCEPTION 'CLAUSE_SCHEMA_OBSERVATION_KIND_UNSEEDED: %', v_count; END IF;
  SELECT pg_get_functiondef('private.migrate_legacy_narrative_record(uuid,text,jsonb)'::regprocedure) INTO v_def;
  IF v_def NOT LIKE '%ob.occurrence_id=v_occurrence.id AND ob.parent_observation_id IS NULL%' THEN
    RAISE EXCEPTION 'CLAUSE_SCHEMA_LEGACY_WRITER_NOT_HARDENED';
  END IF;
  -- Alle fire roller kontrolleres på alle tre relationer: Supabase default-granter
  -- direkte til anon/authenticated/service_role, så REVOKE FROM PUBLIC er ikke nok.
  IF has_function_privilege('authenticated','private.validate_clause_observation()','EXECUTE')
     OR has_function_privilege('service_role','private.validate_clause_observation()','EXECUTE')
     OR has_function_privilege('authenticated','private.validate_clause_disposition()','EXECUTE')
     OR has_function_privilege('service_role','private.validate_clause_disposition()','EXECUTE') THEN
    RAISE EXCEPTION 'CLAUSE_SCHEMA_ACL_INVALID: funktion';
  END IF;
  FOREACH v_rel IN ARRAY ARRAY['private.vocab','private.clause_disposition','private.clause_disposition_current'] LOOP
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      IF has_table_privilege(v_role,v_rel,'SELECT') OR has_table_privilege(v_role,v_rel,'INSERT') THEN
        RAISE EXCEPTION 'CLAUSE_SCHEMA_ACL_INVALID: % har adgang til %', v_role, v_rel;
      END IF;
    END LOOP;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_clause_disposition_append_only' AND tgrelid='private.clause_disposition'::regclass)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_vocab_append_only' AND tgrelid='private.vocab'::regclass)
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private.clause_disposition'::regclass)
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private.vocab'::regclass) THEN
    RAISE EXCEPTION 'CLAUSE_SCHEMA_APPEND_ONLY_MISSING';
  END IF;
  RAISE NOTICE 'OK: #148 klausullagets skema, vokabular, triggere, ACL og hærdet legacy-writer';
END $clause_schema_verify$;

DO $clause_evidence_writer_verify$
BEGIN
  IF to_regprocedure('private.write_clause_evidence(uuid,text,jsonb)') IS NULL
     OR to_regprocedure('public.red_apply_reimport_clause_evidence(uuid,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'CLAUSE_EVIDENCE_WRITER_MISSING';
  END IF;
  IF has_function_privilege('authenticated','private.write_clause_evidence(uuid,text,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_apply_reimport_clause_evidence(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.red_apply_reimport_clause_evidence(uuid,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'CLAUSE_EVIDENCE_WRITER_ACL_INVALID';
  END IF;
  IF pg_get_functiondef('private.validate_reimport_authorization_payload(jsonb,jsonb)'::regprocedure) NOT LIKE '%clause-evidence:%' THEN
    RAISE EXCEPTION 'CLAUSE_EVIDENCE_AUTHORIZATION_FORM_MISSING';
  END IF;
  RAISE NOTICE 'OK: #148 clause_evidence-writer, ACL og autorisationsform';
END $clause_evidence_writer_verify$;

-- Omsegmentering (spec 2026-09-27): historiske migrationsblokke genskaber gamle
-- funktionskroppe. Det levende katalog skal have de nye writere og de selvstændige
-- triggere — ellers kan et forslag knyttes til en erstattet klausul.
DO $clause_set_live_verify$
DECLARE v_def text;
BEGIN
  -- Indeksbytningen i migrationen kender kun navnet ux_source_observation_clause_ordinal.
  -- Står et ældre (parent, ordinal)-indeks under et andet navn, dør hver revision på
  -- dublet-nøgle; derfor skal der være præcis ét ordinal-indeks, og det skal være pr. sæt.
  SELECT indexdef INTO v_def FROM pg_indexes WHERE schemaname='private' AND indexname='ux_source_observation_clause_ordinal';
  IF v_def IS NULL OR v_def NOT LIKE 'CREATE UNIQUE INDEX %' OR v_def NOT LIKE '%COALESCE(clause_set_seq, 1)%' THEN
    RAISE EXCEPTION 'FEJL: ux_source_observation_clause_ordinal er ikke unikt pr. klausulsæt: %', v_def;
  END IF;
  IF (SELECT count(*) FROM pg_indexes WHERE schemaname='private' AND tablename='source_observation' AND indexdef LIKE '%clause_ordinal%')<>1 THEN
    RAISE EXCEPTION 'FEJL: mere end ét indeks over clause_ordinal';
  END IF;
  v_def:=pg_get_functiondef(to_regprocedure('private.write_interpretation_proposal(uuid,text,jsonb)'));
  IF v_def IS NULL OR v_def NOT LIKE '%clause_observation_current%' OR v_def NOT LIKE '%b.source_id=v_batch.source_id%' THEN
    RAISE EXCEPTION 'FEJL: write_interpretation_proposal er ikke sæt-bevidst eller mangler S4-tjekket';
  END IF;
  v_def:=pg_get_functiondef(to_regprocedure('private.write_clause_evidence(uuid,text,jsonb)'));
  IF v_def IS NULL OR v_def NOT LIKE '%private.clause_write_set(%' THEN
    RAISE EXCEPTION 'FEJL: write_clause_evidence skriver ikke via clause_write_set';
  END IF;
  v_def:=pg_get_functiondef(to_regprocedure('private.clause_write_set(jsonb,jsonb,integer,text)'));
  IF v_def IS NULL OR v_def NOT LIKE '%clause_set_seq%' THEN
    RAISE EXCEPTION 'FEJL: clause_write_set sætter ikke clause_set_seq';
  END IF;
  IF (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal AND tgenabled<>'D' AND tgname IN
       ('trg_source_observation_clause_set','trg_clause_set_density','trg_clause_disposition_set_rule',
        'trg_interpretation_observation_current_clause'))<>4 THEN
    RAISE EXCEPTION 'FEJL: klausulsættets triggere mangler eller er slået fra';
  END IF;
  IF to_regprocedure('public.red_apply_reimport_clause_revision(uuid,text,jsonb)') IS NULL
     OR NOT has_function_privilege('authenticated','public.red_apply_reimport_clause_revision(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.red_apply_reimport_clause_revision(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.write_clause_revision(uuid,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'FEJL: clause_revision-RPC mangler eller har forkert ACL';
  END IF;
  RAISE NOTICE 'OK: omsegmentering — indeks pr. sæt, sæt-bevidste writere, S4, triggere og ACL';
END $clause_set_live_verify$;

DO $interpretation_proposal_writer_verify$
BEGIN
  IF to_regprocedure('private.deterministic_uuid(text)') IS NULL
     OR to_regprocedure('private.interpretation_proposal_canonical_json_text(jsonb)') IS NULL
     OR to_regprocedure('private.interpretation_proposal_canonical_json_sha256(jsonb)') IS NULL
     OR to_regprocedure('private.interpretation_proposal_key_material(bigint,text,text,jsonb,jsonb)') IS NULL
     OR to_regprocedure('private.interpretation_proposal_key_material_sha256(bigint,text,text,jsonb,jsonb)') IS NULL
     OR to_regprocedure('private.interpretation_proposal_key(bigint,text,text,jsonb,jsonb)') IS NULL
     OR to_regprocedure('private.write_interpretation_proposal(uuid,text,jsonb)') IS NULL
     OR to_regprocedure('public.red_apply_reimport_interpretation_proposal(uuid,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'MISSING: #147 4.4 interpretation_proposal writer';
  END IF;
  IF pg_get_functiondef('private.validate_reimport_authorization_payload(jsonb,jsonb)'::regprocedure) NOT LIKE '%interpretation-proposal:%'
     OR has_function_privilege('anon','public.red_apply_reimport_interpretation_proposal(uuid,text,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_apply_reimport_interpretation_proposal(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.interpretation_proposal_canonical_json_text(jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.interpretation_proposal_key(bigint,text,text,jsonb,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.write_interpretation_proposal(uuid,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'INVALID: #147 4.4 authorization/ACL';
  END IF;
  -- #196: ingen klientrolle må kalde de private receipt-/nøglehjælpere (review I7).
  IF EXISTS (
    SELECT 1 FROM unnest(ARRAY[
      'private.interpretation_proposal_canonical_json_text(jsonb)',
      'private.interpretation_proposal_canonical_json_sha256(jsonb)',
      'private.normalize_interpretation_proposal_value(jsonb)',
      'private.interpretation_proposal_key_material(bigint,text,text,jsonb,jsonb)',
      'private.interpretation_proposal_key_material_sha256(bigint,text,text,jsonb,jsonb)',
      'private.interpretation_proposal_key(bigint,text,text,jsonb,jsonb)',
      'private.interpretation_proposal_interpretation_receipt(private.interpretation)',
      'private.interpretation_proposal_link_receipt(private.interpretation_observation)',
      'private.interpretation_proposal_disposition_receipt(private.clause_disposition)'
    ]) fn CROSS JOIN unnest(ARRAY['anon','authenticated','service_role']) r
    WHERE to_regprocedure(fn) IS NULL OR has_function_privilege(r, fn, 'EXECUTE')
  ) THEN
    RAISE EXCEPTION 'INVALID: #196 interpretation_proposal receipt helper ACL';
  END IF;
  RAISE NOTICE 'OK: #147 4.4 interpretation_proposal writer, key and ACL';
END $interpretation_proposal_writer_verify$;

-- #147 4.2: prædikat-navnerummet. tests/sql/test-interpretation-predicate.sql dækker
-- CI; denne blok er prod-siden, hvor tabellen skal bevises til stede, bundet og lukket.
-- Bevidst uden nøjagtigt seed-antal: hvert senere dagsværk må kunne tilføje prædikater
-- uden at gøre produktionsverifikationen rød. Fixture-rækkerne tælles derimod præcist,
-- fordi db-verify's egne negative tests afhænger af netop dem.
DO $interpretation_predicate_verify$
DECLARE v_count integer; v_rel text; v_role text;
BEGIN
  IF to_regclass('private.interpretation_predicate') IS NULL
     OR to_regclass('private.interpretation_predicate_promotable') IS NULL THEN
    RAISE EXCEPTION 'PREDICATE_SCHEMA_OBJECTS_MISSING';
  END IF;
  -- Komposit-FK'en er hele pointen: udsagnsformen bindes til prædikatet, ikke kun til
  -- interpretation-tabellens eget CHECK.
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid='private.interpretation'::regclass AND contype='f'
       AND confrelid='private.interpretation_predicate'::regclass
       AND pg_get_constraintdef(oid) LIKE 'FOREIGN KEY (predicate, interpretation_kind)%'
  ) THEN
    RAISE EXCEPTION 'PREDICATE_COMPOSITE_FK_MISSING';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.interpretation_predicate'::regclass AND tgname='trg_interpretation_predicate_validate')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.interpretation_predicate'::regclass AND tgname='trg_interpretation_predicate_mutation')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.interpretation_predicate'::regclass AND tgname='trg_interpretation_predicate_truncate') THEN
    RAISE EXCEPTION 'PREDICATE_TRIGGER_MISSING';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private.interpretation_predicate'::regclass) THEN
    RAISE EXCEPTION 'PREDICATE_RLS_MISSING';
  END IF;
  SELECT count(*) INTO v_count FROM private.interpretation_predicate
   WHERE status='active' AND introduced_in<>'db-verify-fixture';
  IF v_count<42 THEN RAISE EXCEPTION 'PREDICATE_SEED_INCOMPLETE: %', v_count; END IF;
  SELECT count(*) INTO v_count FROM private.interpretation_predicate
   WHERE introduced_in='db-verify-fixture';
  IF v_count<>8 THEN RAISE EXCEPTION 'PREDICATE_FIXTURE_SEED_COUNT: %', v_count; END IF;
  -- Kategorien skal være et seedet vokabular-kodeord, ikke fritekst.
  IF EXISTS (SELECT 1 FROM private.interpretation_predicate p WHERE p.category IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM private.vocab v WHERE v.scheme='interpretation_category' AND v.code=p.category)) THEN
    RAISE EXCEPTION 'PREDICATE_CATEGORY_UNSEEDED';
  END IF;
  -- Reglerne bærer ingen FK (fixture-rækker skal kunne stå der), så deres dækning
  -- måles her i stedet: en regel, hvis prædikat mangler eller har en anden udsagns-
  -- eller værdiform, ville tavst falde ud af promotable-viewet.
  IF EXISTS (
    SELECT 1 FROM private.interpretation_promotion_rule r
     WHERE r.status='active' AND r.rule_key NOT LIKE 'verify-%'
       AND NOT EXISTS (SELECT 1 FROM private.interpretation_predicate p
                        WHERE p.predicate=r.predicate AND p.interpretation_kind=r.interpretation_kind
                          AND p.value_kind=r.value_kind AND p.status='active')
  ) THEN
    RAISE EXCEPTION 'PREDICATE_RULE_BINDING_DRIFT';
  END IF;
  -- Supabase default-granter direkte til rollerne, så REVOKE FROM PUBLIC er ikke nok.
  FOREACH v_rel IN ARRAY ARRAY['private.interpretation_predicate','private.interpretation_predicate_promotable'] LOOP
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      IF has_table_privilege(v_role,v_rel,'SELECT') OR has_table_privilege(v_role,v_rel,'INSERT') THEN
        RAISE EXCEPTION 'PREDICATE_ACL_INVALID: % har adgang til %', v_role, v_rel;
      END IF;
    END LOOP;
  END LOOP;
  IF has_function_privilege('authenticated','private.validate_interpretation_predicate()','EXECUTE')
     OR has_function_privilege('service_role','private.validate_interpretation_predicate()','EXECUTE')
     OR has_function_privilege('authenticated','private.reject_interpretation_predicate_mutation()','EXECUTE')
     OR has_function_privilege('service_role','private.reject_interpretation_predicate_mutation()','EXECUTE') THEN
    RAISE EXCEPTION 'PREDICATE_ACL_INVALID: funktion';
  END IF;
  RAISE NOTICE 'OK: #147 prædikat-navnerummet — tabel, komposit-FK, triggere, regelbinding og ACL';
END $interpretation_predicate_verify$;

-- #154: Global default revoke må ikke efterlade eksisterende public.red_*
-- RPC'er med implicit PUBLIC-adgang eller gøre en ny klient-RPC tavst
-- ukaldbar. Alle undtagelser er eksplicitte og versionsstyrede her.
DO $public_red_acl_verify$
DECLARE
  v_authenticated regprocedure[] := ARRAY[
    'public.red_activate_1939_v50_batch(uuid,uuid)'::regprocedure,
    'public.red_activate_reimport_batch(uuid,uuid)'::regprocedure,
    'public.red_afgoer_relation_interpretation(uuid,integer,text,bigint,text,jsonb)'::regprocedure,
    'public.red_afgoer_source_persona(uuid,integer,text,bigint,text,jsonb)'::regprocedure,
    'public.red_apply_1939_v50_canonical_delta(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_1939_v50_name_completion(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_1939_v50_person_create(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_1939_v50_source_evidence(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_reimport_canonical_delta(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_reimport_name_completion(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_reimport_legacy_migration(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_reimport_clause_evidence(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_reimport_clause_revision(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_reimport_interpretation_proposal(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_reimport_relation_persona(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_reimport_person_create(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_reimport_source_evidence(uuid,text,jsonb)'::regprocedure,
    'public.red_begin_1939_v50_name_completion(uuid,text,uuid)'::regprocedure,
    'public.red_begin_1939_v50_reimport(uuid,text,text)'::regprocedure,
    'public.red_begin_reimport(uuid,text,text)'::regprocedure,
    'public.red_begin_reimport_name_completion(uuid,text,uuid)'::regprocedure,
    'public.red_bekraeft_media_upload(bigint,bigint,text)'::regprocedure,
    'public.red_corroborate_family_identities(uuid,text)'::regprocedure,
    'public.red_decide_interpretation(uuid,integer,text,jsonb)'::regprocedure,
    'public.red_decide_source_persona_placement(uuid,integer,text,jsonb)'::regprocedure,
    'public.red_decide_source_record_placement(uuid,integer,text,jsonb)'::regprocedure,
    'public.red_edit_oplysning(bigint,text,text,text)'::regprocedure,
    'public.red_erstat_media_fil(bigint,text,text,bigint,integer,integer,text,text,jsonb)'::regprocedure,
    'public.red_evaluate_identity_control_run(uuid)'::regprocedure,
    'public.red_finalize_1939_v50_name_completion(uuid)'::regprocedure,
    'public.red_finalize_1939_v50_reimport(uuid)'::regprocedure,
    'public.red_finalize_reimport(uuid)'::regprocedure,
    'public.red_finalize_reimport_name_completion(uuid)'::regprocedure,
    'public.red_fjern_feed_pin(text)'::regprocedure,
    'public.red_fjern_ikke_samme_som(bigint)'::regprocedure,
    'public.red_fjern_media(bigint)'::regprocedure,
    'public.red_fjern_samme_som(bigint)'::regprocedure,
    'public.red_flyt_barn(bigint,bigint,bigint,text)'::regprocedure,
    'public.red_fortryd_change_set(bigint,boolean)'::regprocedure,
    'public.red_fortryd_person_narrative_publication_event(uuid,text)'::regprocedure,
    'public.red_genopret_media(bigint)'::regprocedure,
    'public.red_identity_candidate_input(bigint,jsonb)'::regprocedure,
    'public.red_identity_control_sample(uuid)'::regprocedure,
    'public.red_register_identity_control_run(uuid)'::regprocedure,
    'public.red_relation_persona_input(bigint)'::regprocedure,
    'public.red_ikke_samme_som(bigint,bigint)'::regprocedure,
    'public.red_kasser_person_narrative_record(bigint,bigint,text,text)'::regprocedure,
    'public.red_lock_1939_v50_name_completion(text)'::regprocedure,
    'public.red_lock_reimport_name_completion(text,bigint,text)'::regprocedure,
    'public.red_match_personer()'::regprocedure,
    'public.red_ocr_historik(text,text,text)'::regprocedure,
    'public.red_opdater_media(bigint,text,text,text,text)'::regprocedure,
    'public.red_opret_estate(text,text,bigint)'::regprocedure,
    'public.red_opret_fakta(text,bigint,text,text,date,date,text,text,text)'::regprocedure,
    'public.red_opret_kilde(text,text,text,boolean,smallint)'::regprocedure,
    'public.red_opret_media(text,text,text,text,text,text,text,bigint,integer,integer,text,text,text,boolean)'::regprocedure,
    'public.red_opret_organisation(text,text)'::regprocedure,
    'public.red_opret_person(text,text,boolean,text,text,text)'::regprocedure,
    'public.red_opret_story(text,bigint,text,text,bigint,bigint,bigint,bigint,date,date,text,text,boolean)'::regprocedure,
    'public.red_opret_union(bigint,bigint,text,integer)'::regprocedure,
    'public.red_person_grid()'::regprocedure,
    'public.red_person_narrative_publication_history(bigint)'::regprocedure,
    'public.red_person_narrative_records(bigint)'::regprocedure,
    'public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb)'::regprocedure,
    'public.red_preflight_reimport_authorization(uuid,text,text)'::regprocedure,
    'public.red_preflight_reimport_name_completion(uuid,uuid,text,jsonb)'::regprocedure,
    'public.red_preview_interpretation_promotions(jsonb)'::regprocedure,
    'public.red_preview_reimport_cases(bigint,text,jsonb)'::regprocedure,
    'public.red_promote_interpretations_batch(jsonb,text)'::regprocedure,
    'public.red_publicer_person_narrative_record(bigint,bigint,text,text)'::regprocedure,
    'public.red_publicer_personer(bigint[])'::regprocedure,
    'public.red_publicer_udgave(bigint)'::regprocedure,
    'public.red_record_identity_candidates(jsonb,jsonb)'::regprocedure,
    'public.red_rediger_story(bigint,text,text,bigint,bigint,bigint,bigint,date,date,text,text,boolean)'::regprocedure,
    'public.red_registrer_media_variant(bigint,text,text,text,bigint,integer,integer)'::regprocedure,
    'public.red_reimport_batch_result(uuid,uuid)'::regprocedure,
    'public.red_relation(text,bigint,text,bigint,text,text)'::regprocedure,
    'public.red_ret_ocr_felt(bigint,text,text,text,text,jsonb,text,text)'::regprocedure,
    'public.red_revalider_person_narrative_record(bigint,bigint,text,text)'::regprocedure,
    'public.red_reverse_1939_v50_reimport(uuid,uuid)'::regprocedure,
    'public.red_reverse_reimport(uuid,uuid)'::regprocedure,
    'public.red_revider_publiceret_person_narrative_record(bigint,bigint,text,text,text)'::regprocedure,
    'public.red_saet_portraet(bigint,bigint)'::regprocedure,
    'public.red_samme_som(bigint,bigint)'::regprocedure,
    'public.red_seal_identity_control_run(uuid,text,text)'::regprocedure,
    'public.red_set_familie_konfidens(bigint,bigint,text,text)'::regprocedure,
    'public.red_set_familie_ordinal(bigint,bigint,text,integer)'::regprocedure,
    'public.red_set_feed_pin(text,text)'::regprocedure,
    'public.red_set_haendelse_status(bigint,text)'::regprocedure,
    'public.red_set_koen(bigint,text)'::regprocedure,
    'public.red_set_konklusion(bigint)'::regprocedure,
    'public.red_set_media_rettigheder(bigint,text,boolean,text,text,text,text)'::regprocedure,
    'public.red_set_privat(bigint,boolean)'::regprocedure,
    'public.red_set_story_kilder(bigint,jsonb)'::regprocedure,
    'public.red_set_story_status(bigint,text)'::regprocedure,
    'public.red_slet_familie_link(bigint,bigint,text)'::regprocedure,
    'public.red_slet_medierelation_uden_evidens(bigint)'::regprocedure,
    'public.red_slet_oplysning(bigint)'::regprocedure,
    'public.red_slet_person(bigint)'::regprocedure,
    'public.red_slet_person_preview(bigint)'::regprocedure,
    'public.red_slet_relation(bigint)'::regprocedure,
    'public.red_slet_story(bigint)'::regprocedure,
    'public.red_source_persona_detail(uuid)'::regprocedure,
    'public.red_source_persona_history(uuid)'::regprocedure,
    'public.red_source_persona_queue(text,bigint,uuid,integer,text)'::regprocedure,
    'public.red_suggest(text,text,bigint,text,text,text,jsonb,text)'::regprocedure,
    'public.red_tilbagetraek_fakta(bigint)'::regprocedure,
    'public.red_tilbagetraek_legacy_narrative(uuid,text,text)'::regprocedure,
    'public.red_tilbagetraek_person_narrative_record(bigint,bigint,text,text)'::regprocedure,
    'public.red_tilfoej_barn(bigint,bigint,text,text)'::regprocedure,
    'public.red_tilfoej_foraeldre_paastand(bigint,bigint,bigint,text,text,text)'::regprocedure,
    'public.red_tilfoej_oplysning(bigint,text,date,date,text,text,text)'::regprocedure,
    'public.red_tilfoej_partner(bigint,bigint,integer)'::regprocedure,
    'public.red_tilfoej_relation(bigint,text,bigint,text,text)'::regprocedure,
    'public.red_udrens_media(bigint)'::regprocedure,
    'public.red_udrens_media_preview(bigint)'::regprocedure,
    'public.red_upload_media(text,text,text,text,text,text,bigint,text,bigint,bigint,integer,integer,text,text,text,boolean)'::regprocedure,
    'public.red_upsert_fakta(text,bigint,text,text,date,date,text,text,text)'::regprocedure,
    'public.red_upsert_narrativ(text,bigint,text,boolean,bigint,text)'::regprocedure,
    'public.red_upsert_person_narrative_record(bigint,bigint,text,text,boolean,text)'::regprocedure,
    'public.red_vaelg_foraeldre(bigint,text)'::regprocedure
  ];
  v_service_only regprocedure[] := ARRAY[
    'public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamptz)'::regprocedure,
    'public.red_authorize_1939_v50_reversal(uuid,uuid,timestamptz)'::regprocedure,
    'public.red_authorize_1939_v50_cutover(uuid,uuid,timestamptz)'::regprocedure,
    'public.red_authorize_1939_v50_name_completion(text,uuid,text,text,jsonb,jsonb)'::regprocedure,
    'public.red_authorize_reimport(text,text,text,bigint,text,text,jsonb,jsonb,uuid,timestamptz)'::regprocedure,
    'public.red_authorize_reimport_reversal(uuid,uuid,timestamptz)'::regprocedure,
    'public.red_authorize_reimport_cutover(uuid,uuid,timestamptz)'::regprocedure,
    'public.red_authorize_reimport_name_completion(text,uuid,text,text,bigint,text,text,jsonb,jsonb)'::regprocedure
  ];
  v_disabled regprocedure[] := ARRAY[
    'public.red_promote_interpretation(uuid,text,bigint,jsonb)'::regprocedure,
    'public.red_publicer_narrative_record(bigint,uuid,text,text)'::regprocedure,
    'public.red_tilbagetraek_narrative_record(bigint)'::regprocedure,
    'public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)'::regprocedure,
    'public.red_apply_reimport_cases(uuid,text,text)'::regprocedure,
    'public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)'::regprocedure,
    'public.red_reverse_reimport_cases(uuid,uuid)'::regprocedure
  ];
  v_bad text[];
  v_error text;
BEGIN
  SELECT array_agg(p.oid::regprocedure::text ORDER BY p.oid::regprocedure::text)
    INTO v_bad
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.proname LIKE 'red\_%' ESCAPE '\'
     AND (
       EXISTS (
         SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
          WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'
       )
       OR has_function_privilege('anon',p.oid,'EXECUTE')
       OR (p.oid=ANY(v_service_only) AND (
             has_function_privilege('authenticated',p.oid,'EXECUTE')
             OR NOT has_function_privilege('service_role',p.oid,'EXECUTE')
           ))
       OR (p.oid=ANY(v_disabled) AND (
             has_function_privilege('authenticated',p.oid,'EXECUTE')
             OR has_function_privilege('service_role',p.oid,'EXECUTE')
           ))
       OR (p.oid=ANY(v_authenticated) AND (
             NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
             OR has_function_privilege('service_role',p.oid,'EXECUTE')
           ))
       OR (p.oid<>ALL(v_authenticated)
           AND p.oid<>ALL(v_service_only)
           AND p.oid<>ALL(v_disabled))
     );
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'EVIDENCE_PUBLIC_RED_ACL_DRIFT: %',v_bad;
  END IF;

  EXECUTE $sql$CREATE FUNCTION public.red_evidence_acl_verify()
    RETURNS integer LANGUAGE sql AS 'SELECT 1'$sql$;
  v_error:=NULL;
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM public.red_evidence_acl_verify();
  EXCEPTION WHEN insufficient_privilege THEN v_error:=SQLERRM;
  END;
  IF v_error IS NULL THEN
    RAISE EXCEPTION 'EVIDENCE_PUBLIC_RED_DEFAULT_ACL_ANON_OPEN';
  END IF;
  v_error:=NULL;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.red_evidence_acl_verify();
  EXCEPTION WHEN insufficient_privilege THEN v_error:=SQLERRM;
  END;
  IF v_error IS NULL THEN
    RAISE EXCEPTION 'EVIDENCE_PUBLIC_RED_DEFAULT_ACL_AUTH_OPEN';
  END IF;
  GRANT EXECUTE ON FUNCTION public.red_evidence_acl_verify() TO authenticated;
  SET LOCAL ROLE authenticated;
  IF public.red_evidence_acl_verify()<>1 THEN
    RAISE EXCEPTION 'EVIDENCE_PUBLIC_RED_EXPLICIT_AUTH_GRANT_FAILED';
  END IF;
  RESET ROLE;
  v_error:=NULL;
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM public.red_evidence_acl_verify();
  EXCEPTION WHEN insufficient_privilege THEN v_error:=SQLERRM;
  END;
  IF v_error IS NULL THEN
    RAISE EXCEPTION 'EVIDENCE_PUBLIC_RED_EXPLICIT_AUTH_GRANT_OPENED_ANON';
  END IF;
  DROP FUNCTION public.red_evidence_acl_verify();
  RAISE NOTICE 'OK: public.red_* har eksplicit, least-privilege EXECUTE-policy';
END $public_red_acl_verify$;

-- Reel to-forbindelses-test: occurrence-låsen skal serialisere to samtidige
-- accepted-events, så præcis én vinder. Kun aktiv i disposable baser med dblink.
DO $evidence_concurrency$
DECLARE
  v_conn text := format(
    'dbname=%s port=%s host=%s', current_database(), current_setting('port'),
    split_part(current_setting('unix_socket_directories'),',',1)
  );
  v_actor uuid := '10000000-0000-0000-0000-000000000011';
  v_occurrence uuid := '50000000-0000-0000-0000-000000000011';
  v_record_a uuid := '40000000-0000-0000-0000-000000000011';
  v_record_b uuid := '40000000-0000-0000-0000-000000000012';
  v_a_pid integer;
  v_b_pid integer;
  v_busy integer;
  v_deadline timestamptz;
  v_error text;
  v_setup_connected boolean := false;
  v_a_connected boolean := false;
  v_b_connected boolean := false;
  v_cleanup text := $cleanup$
    SET session_replication_role=replica;
    DELETE FROM private.source_record_anchor_event
      WHERE occurrence_id='50000000-0000-0000-0000-000000000011';
    DELETE FROM private.source_record_occurrence
      WHERE id='50000000-0000-0000-0000-000000000011';
    DELETE FROM private.source_record
      WHERE id IN ('40000000-0000-0000-0000-000000000011','40000000-0000-0000-0000-000000000012');
    DELETE FROM private.source_rendition
      WHERE id='30000000-0000-0000-0000-000000000011';
    DELETE FROM private.extraction_run
      WHERE id='20000000-0000-0000-0000-000000000011';
    DELETE FROM source WHERE id=-987650011;
    DELETE FROM auth.users WHERE id='10000000-0000-0000-0000-000000000011';
    SET session_replication_role=origin;
  $cleanup$;
BEGIN
  IF to_regprocedure('dblink_connect(text,text)') IS NULL THEN
    RAISE EXCEPTION 'DB_VERIFY_DBLINK_REQUIRED: evidens-anchor samtidighed';
  END IF;

  PERFORM dblink_connect('evidence_setup',v_conn || ' application_name=daa_verify_evidence_setup');
  v_setup_connected := true;
  PERFORM dblink_exec('evidence_setup',v_cleanup);
  PERFORM dblink_exec('evidence_setup',format(
    'INSERT INTO auth.users(id,email) VALUES (''%s'',''evidence-lock@test.invalid'')',v_actor));
  PERFORM dblink_exec('evidence_setup',
    'INSERT INTO source(id,titel,import_key) VALUES (-987650011,''Evidence lock'',''verify:evidence:lock'')');
  PERFORM dblink_exec('evidence_setup',
    'INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) '
    || 'VALUES (''20000000-0000-0000-0000-000000000011'',-987650011,''lock-run'',''1.0'',''verify'',''verify'','
    || quote_literal(repeat('e',64)) || ',''{}'')');
  PERFORM dblink_exec('evidence_setup',
    'INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata) '
    || 'VALUES (''30000000-0000-0000-0000-000000000011'',-987650011,''lock-rendition'',''text_layer'','
    || quote_literal(repeat('f',64)) || ',''{}'')');
  PERFORM dblink_exec('evidence_setup',
    'INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id) VALUES '
    || '(''40000000-0000-0000-0000-000000000011'',-987650011,''lock-a'',''person_entry'',''20000000-0000-0000-0000-000000000011''),'
    || '(''40000000-0000-0000-0000-000000000012'',-987650011,''lock-b'',''person_entry'',''20000000-0000-0000-0000-000000000011'')');
  PERFORM dblink_exec('evidence_setup',
    'INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id) '
    || 'VALUES (''50000000-0000-0000-0000-000000000011'',''30000000-0000-0000-0000-000000000011'',''lock-occurrence'',1,1,0,4,''Lock'',''physical'',''structural'',''20000000-0000-0000-0000-000000000011'')');

  PERFORM dblink_connect('evidence_a',v_conn || ' application_name=daa_verify_evidence_a');
  v_a_connected := true;
  PERFORM dblink_connect('evidence_b',v_conn || ' application_name=daa_verify_evidence_b');
  v_b_connected := true;
  SELECT pid INTO v_a_pid FROM dblink('evidence_a','SELECT pg_backend_pid()') AS t(pid integer);
  SELECT pid INTO v_b_pid FROM dblink('evidence_b','SELECT pg_backend_pid()') AS t(pid integer);

  PERFORM dblink_exec('evidence_a','BEGIN');
  PERFORM dblink_exec('evidence_a',format(
    'INSERT INTO private.source_record_anchor_event(id,occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name) '
    || 'VALUES (''90000000-0000-0000-0000-000000000011'',''%s'',''%s'',''accepted'',''{"basis":"A"}'',1,''%s'',''A'')',
    v_occurrence,v_record_a,v_actor));

  PERFORM dblink_exec('evidence_b','BEGIN');
  PERFORM dblink_send_query('evidence_b',format(
    'INSERT INTO private.source_record_anchor_event(id,occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name) '
    || 'VALUES (''90000000-0000-0000-0000-000000000012'',''%s'',''%s'',''accepted'',''{"basis":"B"}'',1,''%s'',''B'') RETURNING id',
    v_occurrence,v_record_b,v_actor));
  v_deadline := clock_timestamp() + interval '3 seconds';
  LOOP
    EXIT WHEN v_a_pid=ANY(pg_blocking_pids(v_b_pid));
    SELECT dblink_is_busy('evidence_b') INTO v_busy;
    IF v_busy=0 OR clock_timestamp()>v_deadline THEN
      RAISE EXCEPTION 'FEJL: anden anchor-writer blev ikke serialiseret på occurrence';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;

  PERFORM dblink_exec('evidence_a','COMMIT');
  v_deadline := clock_timestamp() + interval '3 seconds';
  LOOP
    SELECT dblink_is_busy('evidence_b') INTO v_busy;
    EXIT WHEN v_busy=0;
    IF clock_timestamp()>v_deadline THEN
      RAISE EXCEPTION 'FEJL: anden anchor-writer afsluttede ikke efter første COMMIT';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  v_error := NULL;
  BEGIN
    PERFORM * FROM dblink_get_result('evidence_b') AS t(id uuid);
  EXCEPTION WHEN others THEN v_error := SQLERRM; END;
  -- Asynkrone dblink-kald har et afsluttende tomt resultat efter selve fejlen.
  -- Tøm det, før forbindelsen kan modtage ROLLBACK.
  BEGIN
    PERFORM * FROM dblink_get_result('evidence_b') AS t(id uuid);
  EXCEPTION WHEN others THEN
    IF v_error IS NULL THEN v_error := SQLERRM; END IF;
  END;
  IF v_error NOT LIKE '%EVIDENCE_ANCHOR_CONFLICT%' THEN
    RAISE EXCEPTION 'FEJL: samtidig accepted-anchor tabte ikke fail-closed: %',v_error;
  END IF;
  PERFORM dblink_exec('evidence_b','ROLLBACK');
  PERFORM dblink_disconnect('evidence_a'); v_a_connected := false;
  PERFORM dblink_disconnect('evidence_b'); v_b_connected := false;

  IF (SELECT count(*) FROM private.source_record_anchor_current
       WHERE occurrence_id=v_occurrence AND decision_status='accepted') <> 1 THEN
    RAISE EXCEPTION 'FEJL: samtidighedstesten efterlod ikke præcis én accepted anchor';
  END IF;
  PERFORM dblink_exec('evidence_setup',v_cleanup);
  PERFORM dblink_disconnect('evidence_setup'); v_setup_connected := false;
  PERFORM set_config('daa.verify_dblink_evidence_anchor','executed',false);
  RAISE NOTICE 'OK: source_record_anchor_event serialiserer samtidige accepted-afgørelser';
EXCEPTION WHEN others THEN
  IF v_a_connected THEN
    BEGIN PERFORM dblink_exec('evidence_a','ROLLBACK'); EXCEPTION WHEN others THEN NULL; END;
    BEGIN PERFORM dblink_disconnect('evidence_a'); EXCEPTION WHEN others THEN NULL; END;
  END IF;
  IF v_b_connected THEN
    BEGIN PERFORM dblink_exec('evidence_b','ROLLBACK'); EXCEPTION WHEN others THEN NULL; END;
    BEGIN PERFORM dblink_disconnect('evidence_b'); EXCEPTION WHEN others THEN NULL; END;
  END IF;
  IF v_setup_connected THEN
    BEGIN PERFORM dblink_exec('evidence_setup',v_cleanup); EXCEPTION WHEN others THEN NULL; END;
    BEGIN PERFORM dblink_disconnect('evidence_setup'); EXCEPTION WHEN others THEN NULL; END;
  END IF;
  RAISE;
END $evidence_concurrency$;

-- En accepted anchor, der vinder kapløbet om en hidtil frisk successor, skal
-- få den konkurrerende accepted revision til at vente og derefter afvise den.
DO $revision_anchor_concurrency$
DECLARE
  v_conn text := format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),split_part(current_setting('unix_socket_directories'),',',1));
  v_actor uuid := '10000000-0000-0000-0000-000000000071';
  v_a_pid integer;
  v_b_pid integer;
  v_busy integer;
  v_deadline timestamptz;
  v_error text;
  v_setup_connected boolean := false;
  v_a_connected boolean := false;
  v_b_connected boolean := false;
  v_cleanup text := $cleanup$
    SET session_replication_role=replica;
    DELETE FROM private.source_record_revision_event WHERE predecessor_record_id='40000000-0000-0000-0000-000000000071';
    DELETE FROM private.source_record_anchor_event WHERE occurrence_id='50000000-0000-0000-0000-000000000071';
    DELETE FROM private.source_record_occurrence WHERE id='50000000-0000-0000-0000-000000000071';
    DELETE FROM private.source_record WHERE id IN ('40000000-0000-0000-0000-000000000071','40000000-0000-0000-0000-000000000072');
    DELETE FROM private.source_rendition WHERE id='30000000-0000-0000-0000-000000000071';
    DELETE FROM private.extraction_run WHERE id='20000000-0000-0000-0000-000000000071';
    DELETE FROM source WHERE id=-987650071;
    DELETE FROM auth.users WHERE id='10000000-0000-0000-0000-000000000071';
    SET session_replication_role=origin;
  $cleanup$;
BEGIN
  IF to_regprocedure('dblink_connect(text,text)') IS NULL THEN
    RAISE EXCEPTION 'DB_VERIFY_DBLINK_REQUIRED: revision-anchor samtidighed';
  END IF;
  PERFORM dblink_connect('revision_anchor_setup',v_conn||' application_name=daa_verify_revision_anchor_setup');
  v_setup_connected:=true;
  PERFORM dblink_exec('revision_anchor_setup',v_cleanup);
  PERFORM dblink_exec('revision_anchor_setup','INSERT INTO auth.users(id,email) VALUES (''10000000-0000-0000-0000-000000000071'',''revision-anchor@test.invalid'')');
  PERFORM dblink_exec('revision_anchor_setup','INSERT INTO source(id,titel,import_key) VALUES (-987650071,''Revision anchor lock'',''verify:revision-anchor:lock'')');
  PERFORM dblink_exec('revision_anchor_setup','INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) VALUES (''20000000-0000-0000-0000-000000000071'',-987650071,''revision-anchor-run'',''1.0'',''verify'',''verify'',''' || repeat('7',64) || ''',''{}'')');
  PERFORM dblink_exec('revision_anchor_setup','INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata) VALUES (''30000000-0000-0000-0000-000000000071'',-987650071,''revision-anchor-rendition'',''text_layer'',''' || repeat('8',64) || ''',''{}'')');
  PERFORM dblink_exec('revision_anchor_setup','INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id) VALUES (''40000000-0000-0000-0000-000000000071'',-987650071,''revision-predecessor'',''person_entry'',''20000000-0000-0000-0000-000000000071''),(''40000000-0000-0000-0000-000000000072'',-987650071,''revision-successor'',''person_entry'',''20000000-0000-0000-0000-000000000071'')');
  PERFORM dblink_exec('revision_anchor_setup','INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id) VALUES (''50000000-0000-0000-0000-000000000071'',''30000000-0000-0000-0000-000000000071'',''revision-anchor-occurrence'',1,1,0,4,''Lock'',''revision-anchor-physical'',''revision-anchor-structural'',''20000000-0000-0000-0000-000000000071'')');
  PERFORM dblink_connect('revision_anchor_a',v_conn||' application_name=daa_verify_revision_a'); v_a_connected:=true;
  PERFORM dblink_connect('revision_anchor_b',v_conn||' application_name=daa_verify_anchor_b'); v_b_connected:=true;
  SELECT pid INTO v_a_pid FROM dblink('revision_anchor_a','SELECT pg_backend_pid()') AS t(pid integer);
  SELECT pid INTO v_b_pid FROM dblink('revision_anchor_b','SELECT pg_backend_pid()') AS t(pid integer);
  PERFORM dblink_exec('revision_anchor_b','BEGIN');
  PERFORM dblink_exec('revision_anchor_b','INSERT INTO private.source_record_anchor_event(id,occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name) VALUES (''90000000-0000-0000-0000-000000000071'',''50000000-0000-0000-0000-000000000071'',''40000000-0000-0000-0000-000000000072'',''accepted'',''{"basis":"B"}'',1,''10000000-0000-0000-0000-000000000071'',''B'')');
  PERFORM dblink_exec('revision_anchor_a','BEGIN');
  PERFORM dblink_send_query('revision_anchor_a','INSERT INTO private.source_record_revision_event(id,predecessor_record_id,successor_record_id,relation_kind,decision_status,evidence,version,decided_by,decided_by_name) VALUES (''a0000000-0000-0000-0000-000000000071'',''40000000-0000-0000-0000-000000000071'',''40000000-0000-0000-0000-000000000072'',''split_into'',''accepted'',''{"basis":"A"}'',1,''10000000-0000-0000-0000-000000000071'',''A'')');
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP
    EXIT WHEN v_b_pid=ANY(pg_blocking_pids(v_a_pid));
    SELECT dblink_is_busy('revision_anchor_a') INTO v_busy;
    IF v_busy=0 OR clock_timestamp()>v_deadline THEN RAISE EXCEPTION 'FEJL: revision ventede ikke på accepted anchor'; END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  PERFORM dblink_exec('revision_anchor_b','COMMIT');
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP SELECT dblink_is_busy('revision_anchor_a') INTO v_busy; EXIT WHEN v_busy=0;
    IF clock_timestamp()>v_deadline THEN RAISE EXCEPTION 'FEJL: revision-anchor race afsluttede ikke'; END IF;
    PERFORM pg_sleep(0.02); END LOOP;
  v_error:=NULL;
  BEGIN PERFORM * FROM dblink_get_result('revision_anchor_a') AS t(id uuid);
  EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
  BEGIN PERFORM * FROM dblink_get_result('revision_anchor_a') AS t(id uuid);
  EXCEPTION WHEN others THEN IF v_error IS NULL THEN v_error:=SQLERRM; END IF; END;
  IF v_error NOT LIKE '%EVIDENCE_REVISION_SUCCESSOR_ALREADY_ANCHORED%' THEN
    RAISE EXCEPTION 'FEJL: concurrent accepted revision blev ikke afvist: %',v_error;
  END IF;
  PERFORM dblink_exec('revision_anchor_a','ROLLBACK');
  PERFORM dblink_disconnect('revision_anchor_a'); v_a_connected:=false;
  PERFORM dblink_disconnect('revision_anchor_b'); v_b_connected:=false;
  PERFORM dblink_exec('revision_anchor_setup',v_cleanup);
  PERFORM dblink_disconnect('revision_anchor_setup'); v_setup_connected:=false;
  PERFORM set_config('daa.verify_dblink_revision_anchor','executed',false);
  RAISE NOTICE 'OK: accepted anchor serialiserer concurrent accepted revision';
EXCEPTION WHEN others THEN
  IF v_a_connected THEN BEGIN PERFORM dblink_exec('revision_anchor_a','ROLLBACK'); EXCEPTION WHEN others THEN NULL; END; BEGIN PERFORM dblink_disconnect('revision_anchor_a'); EXCEPTION WHEN others THEN NULL; END; END IF;
  IF v_b_connected THEN BEGIN PERFORM dblink_exec('revision_anchor_b','ROLLBACK'); EXCEPTION WHEN others THEN NULL; END; BEGIN PERFORM dblink_disconnect('revision_anchor_b'); EXCEPTION WHEN others THEN NULL; END; END IF;
  IF v_setup_connected THEN BEGIN PERFORM dblink_exec('revision_anchor_setup',v_cleanup); EXCEPTION WHEN others THEN NULL; END; BEGIN PERFORM dblink_disconnect('revision_anchor_setup'); EXCEPTION WHEN others THEN NULL; END; END IF;
  RAISE;
END $revision_anchor_concurrency$;

-- ===== Evidensimport Fase 3 / Task 6: slægt, lineage og kildeschemes =====
DO $slaegt_verify$
DECLARE
  v_required_public text[] := ARRAY[
    'slaegt','lineage_scheme','lineage_scheme_entry',
    'lineage_scheme_entry_lineage','person_slaegt_membership',
    'person_lineage_membership','person_source_coordinate_legacy'
  ];
  v_required_private text[] := ARRAY[
    'source_record_placement','source_persona_placement',
    'source_record_placement_decision','source_persona_placement_decision',
    'source_record_placement_current','source_persona_placement_current'
  ];
  v_missing text[];
  v_slaegt_a bigint;
  v_slaegt_b bigint;
  v_scheme_a bigint;
  v_scheme_b bigint;
  v_presens_scheme bigint;
  v_entry_a bigint;
  v_entry_b bigint;
  v_presens_entry bigint;
  v_lineage_a bigint;
  v_lineage_b bigint;
  v_run uuid := 'a6000000-0000-0000-0000-000000000061';
  v_rendition uuid := 'a6000000-0000-0000-0000-000000000062';
  v_record_a uuid := 'a6000000-0000-0000-0000-000000000063';
  v_record_b uuid := 'a6000000-0000-0000-0000-000000000064';
  v_occurrence_a uuid := 'a6000000-0000-0000-0000-000000000065';
  v_occurrence_b uuid := 'a6000000-0000-0000-0000-000000000066';
  v_observation_a uuid := 'a6000000-0000-0000-0000-000000000067';
  v_observation_b uuid := 'a6000000-0000-0000-0000-000000000068';
  v_observation_nonheader uuid := 'a6000000-0000-0000-0000-00000000006a';
  v_persona uuid := 'a6000000-0000-0000-0000-000000000069';
  v_mention uuid := 'a6000000-0000-0000-0000-00000000006b';
  v_actor uuid := 'a6000000-0000-0000-0000-00000000006c';
  v_placement uuid;
  v_persona_placement uuid;
  v_rejected_placement uuid;
  v_version integer;
  v_error text;
BEGIN
  SELECT array_agg(required_name ORDER BY required_name) INTO v_missing
    FROM unnest(v_required_public) AS required_name
   WHERE to_regclass(format('public.%I',required_name)) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: Task 6 mangler offentlige modelobjekter: %',v_missing;
  END IF;
  SELECT array_agg(required_name ORDER BY required_name) INTO v_missing
    FROM unnest(v_required_private) AS required_name
   WHERE to_regclass(format('private.%I',required_name)) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: Task 6 mangler private placement-objekter: %',v_missing;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='lineage'
       AND column_name='slaegt_id'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='lineage'
       AND column_name='canonical_label'
  ) THEN
    RAISE EXCEPTION 'FEJL: lineage mangler slægt- eller canonical_label-kontekst';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='private' AND table_name='source_record_placement'
       AND column_name='header_observation_id' AND is_nullable='NO'
  ) THEN
    RAISE EXCEPTION 'FEJL: source_record_placement mangler obligatorisk header-observation';
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='private'
       AND table_name IN ('source_record_placement','source_persona_placement')
       AND column_name='status'
  ) OR (SELECT count(*) FROM information_schema.columns
         WHERE table_schema='private'
           AND table_name IN ('source_record_placement','source_persona_placement')
           AND column_name='initial_status')<>2 THEN
    RAISE EXCEPTION 'FEJL: placement-basekolonnen ligner stadig autoritativ status';
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='person'
       AND column_name IN ('slaegtled_lokal','slaegtled_gennem','generation_local','generation_global')
  ) THEN
    RAISE EXCEPTION 'FEJL: genealogisk generation blev gjort til global person-attribut';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(v_required_public) AS required_name
     JOIN pg_class c ON c.oid=to_regclass(format('public.%I',required_name))
     WHERE c.relkind='r' AND NOT c.relrowsecurity
  ) OR EXISTS (
    SELECT 1 FROM unnest(v_required_private) AS required_name
     JOIN pg_class c ON c.oid=to_regclass(format('private.%I',required_name))
     WHERE c.relkind='r' AND NOT c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'FEJL: Task 6-modelobjekt mangler RLS';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(v_required_private) AS required_name
     WHERE has_table_privilege('anon',format('private.%I',required_name),'SELECT')
        OR has_table_privilege('authenticated',format('private.%I',required_name),'SELECT')
        OR has_table_privilege('authenticated',format('private.%I',required_name),'INSERT')
  ) OR has_table_privilege('anon','public.person_slaegt_membership','SELECT')
     OR has_table_privilege('authenticated','public.person_lineage_membership','SELECT')
     OR NOT has_table_privilege('anon','public.person_source_coordinate_legacy','SELECT') THEN
    RAISE EXCEPTION 'FEJL: Task 6 har forkert direkte API-adgang';
  END IF;

  BEGIN
    INSERT INTO auth.users(id,email) VALUES (v_actor,'placement-verify@test.invalid');
    INSERT INTO public.profiles(id,rolle,navn,email)
      VALUES (v_actor,'redaktion','Placement Verify','placement-verify@test.invalid');
    INSERT INTO public.slaegt(navn,sorteringsnavn,slug,status)
      VALUES ('Verify slægt A','Verify slægt A','verify-slaegt-a','active')
      RETURNING id INTO v_slaegt_a;
    INSERT INTO public.slaegt(navn,sorteringsnavn,slug,status)
      VALUES ('Verify slægt B','Verify slægt B','verify-slaegt-b','active')
      RETURNING id INTO v_slaegt_b;
    INSERT INTO public.lineage(slaegt_id,canonical_label,navn)
      VALUES (v_slaegt_a,'II. linje','Verify lineage A') RETURNING id INTO v_lineage_a;
    INSERT INTO public.lineage(slaegt_id,canonical_label,navn)
      VALUES (v_slaegt_b,'II. linje','Verify lineage B') RETURNING id INTO v_lineage_b;
    INSERT INTO public.lineage_scheme(slaegt_id,kind,label)
      VALUES (v_slaegt_a,'stamtavle','Verify A') RETURNING id INTO v_scheme_a;
    INSERT INTO public.lineage_scheme(slaegt_id,kind,label)
      VALUES (v_slaegt_b,'stamtavle','Verify B') RETURNING id INTO v_scheme_b;
    INSERT INTO public.lineage_scheme(slaegt_id,kind,label)
      VALUES (v_slaegt_a,'presensliste','Verify A præsens') RETURNING id INTO v_presens_scheme;
    INSERT INTO public.lineage_scheme_entry(scheme_id,slaegt_id,code,label,sort_order)
      VALUES (v_scheme_a,v_slaegt_a,'II','II. linje',2) RETURNING id INTO v_entry_a;
    INSERT INTO public.lineage_scheme_entry(scheme_id,slaegt_id,code,label,sort_order)
      VALUES (v_scheme_b,v_slaegt_b,'II','II. linje',2) RETURNING id INTO v_entry_b;
    INSERT INTO public.lineage_scheme_entry(scheme_id,slaegt_id,code,label,sort_order)
      VALUES (v_presens_scheme,v_slaegt_a,'V','V. linje',5) RETURNING id INTO v_presens_entry;
    INSERT INTO public.lineage_scheme_entry_lineage(entry_id,lineage_id,slaegt_id,relation_kind)
      VALUES (v_entry_a,v_lineage_a,v_slaegt_a,'canonical'),
             (v_entry_b,v_lineage_b,v_slaegt_b,'canonical'),
             (v_presens_entry,v_lineage_a,v_slaegt_a,'canonical');
    v_error:=NULL;
    BEGIN
      INSERT INTO public.lineage_scheme_entry_lineage(entry_id,lineage_id,slaegt_id,relation_kind)
        VALUES (v_entry_a,v_lineage_b,v_slaegt_a,'canonical');
    EXCEPTION WHEN foreign_key_violation THEN v_error:=SQLERRM; END;
    IF v_error IS NULL THEN
      RAISE EXCEPTION 'FEJL: cross-clan lineage mapping blev accepteret';
    END IF;
    IF (SELECT count(*) FROM pg_constraint WHERE conname IN (
         'lineage_scheme_id_slaegt_uidx','lineage_id_slaegt_uidx',
         'lineage_scheme_entry_id_slaegt_uidx','lineage_scheme_entry_scheme_slaegt_fkey',
         'lineage_scheme_entry_lineage_entry_slaegt_fkey',
         'lineage_scheme_entry_lineage_lineage_slaegt_fkey'
       )) <> 6 THEN
      RAISE EXCEPTION 'FEJL: lineage mangler deklarative slægtsconstraints';
    END IF;
    IF (SELECT count(*) FROM public.lineage_scheme_entry WHERE code='II') < 2 THEN
      RAISE EXCEPTION 'FEJL: samme kode II kunne ikke eksistere i to slægts-schemes';
    END IF;
    IF (SELECT count(*) FROM public.lineage_scheme_entry_lineage
         WHERE lineage_id=v_lineage_a AND relation_kind='canonical') <> 2 THEN
      RAISE EXCEPTION 'FEJL: samme lineage kunne ikke have forskellige stamtavle-/præsenskoder';
    END IF;
    INSERT INTO public.person(id) VALUES (-987650061);
    INSERT INTO public.person_slaegt_membership(person_id,slaegt_id,membership_kind,source_basis)
      VALUES (-987650061,v_slaegt_a,'agnatic','{"basis":"verify"}'),
             (-987650061,v_slaegt_b,'cognatic','{"basis":"verify"}');
    INSERT INTO public.person_lineage_membership(person_id,lineage_id,role,source_basis)
      VALUES (-987650061,v_lineage_a,'member','{"basis":"verify"}'),
             (-987650061,v_lineage_b,'founder','{"basis":"verify"}');
    IF (SELECT count(*) FROM public.person WHERE id=-987650061)<>1
       OR (SELECT count(*) FROM public.person_lineage_membership WHERE person_id=-987650061)<>2 THEN
      RAISE EXCEPTION 'FEJL: flere lineage-medlemskaber skabte ikke præcis én person';
    END IF;
    v_error:=NULL;
    BEGIN
      INSERT INTO public.person_slaegt_membership(person_id,slaegt_id,membership_kind,source_basis)
        VALUES (-987650061,v_slaegt_a,'affinal','{"basis":"spouse"}');
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    IF v_error IS NULL THEN
      RAISE EXCEPTION 'FEJL: indgiftethed kunne oprettes som slægtsmedlemskab';
    END IF;
    INSERT INTO public.source(id,titel) VALUES (-987650061,'Task 6 evidence source');
    INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,
                                       profile_version,input_sha256)
      VALUES (v_run,-987650061,'task6','v1','verify','verify',repeat('a',64));
    INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256)
      VALUES (v_rendition,-987650061,'task6','ocr',repeat('b',64));
    INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id) VALUES
      (v_record_a,-987650061,'task6-a','person',v_run),
      (v_record_b,-987650061,'task6-b','person',v_run);
    INSERT INTO private.source_record_occurrence(
      id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,
      physical_fingerprint,structural_fingerprint,extraction_run_id
    ) VALUES
      (v_occurrence_a,v_rendition,'task6-a',1,1,0,12,'A observation','physical-a','structural-a',v_run),
      (v_occurrence_b,v_rendition,'task6-b',2,2,0,12,'B observation','physical-b','structural-b',v_run);
    INSERT INTO private.source_record_anchor_event(
      occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name
    ) VALUES
      (v_occurrence_a,v_record_a,'accepted','{"basis":"verify"}',1,
       'a6000000-0000-0000-0000-000000000060','Task 6 verify'),
      (v_occurrence_b,v_record_b,'accepted','{"basis":"verify"}',1,
       'a6000000-0000-0000-0000-000000000060','Task 6 verify');
    INSERT INTO private.source_observation(
      id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,
      quality_status,extraction_method,extraction_run_id
    ) VALUES
      (v_observation_a,v_occurrence_a,'header',1,1,0,12,'A observation','clear','verify',v_run),
      (v_observation_b,v_occurrence_b,'header',2,2,0,12,'B observation','clear','verify',v_run),
      (v_observation_nonheader,v_occurrence_a,'name_clause',1,1,0,12,'A observation','clear','verify',v_run);
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
      VALUES (v_persona,-987650061,'task6-persona',v_run);
    INSERT INTO private.source_mention(
      id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id
    ) VALUES (v_mention,v_observation_a,'person_name',0,12,'A observatio',v_run);
    INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
      VALUES (v_persona,v_mention,'primary',1);
    v_error:=NULL;
    BEGIN
      INSERT INTO private.source_record_placement(
        source_record_id,scheme_entry_id,header_observation_id
      ) VALUES (v_record_a,v_entry_a,v_observation_nonheader);
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    IF v_error NOT LIKE '%EVIDENCE_PLACEMENT_HEADER_REQUIRED%' THEN
      RAISE EXCEPTION 'FEJL: record-placering accepterede ikke-header-observation: %',v_error;
    END IF;
    INSERT INTO private.source_record_placement(
      source_record_id,scheme_entry_id,header_observation_id
    ) VALUES (v_record_a,v_entry_a,v_observation_a) RETURNING id INTO v_placement;
    INSERT INTO private.source_record_placement_decision(
      placement_id,version,decision_status,evidence,decision_origin,decided_by_name
    ) VALUES (v_placement,1,'proposed','{"basis":"verify proposal"}','ingest','verify ingest');
    INSERT INTO private.source_persona_placement(
      source_persona_id,record_placement_id,placement_role,basis_observation_id
    ) VALUES (v_persona,v_placement,'principal_member',v_observation_a)
      RETURNING id INTO v_persona_placement;
    INSERT INTO private.source_persona_placement_decision(
      placement_id,version,decision_status,evidence,decision_origin,decided_by_name
    ) VALUES (v_persona_placement,1,'proposed','{"basis":"verify proposal"}','ingest','verify ingest');
    v_error:=NULL;
    BEGIN
      INSERT INTO private.source_persona_placement(
        source_persona_id,record_placement_id,placement_role,basis_observation_id
      ) VALUES (v_persona,v_placement,'mentioned_spouse',v_observation_nonheader);
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    IF v_error NOT LIKE '%EVIDENCE_PERSONA_PLACEMENT_BASIS_REQUIRED%' THEN
      RAISE EXCEPTION 'FEJL: persona-placering krævede ikke egen record-forankret observation: %',v_error;
    END IF;
    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    SET LOCAL ROLE authenticated;
    SELECT red_decide_source_record_placement(v_placement,1,'accepted','{"basis":"review"}') INTO v_version;
    IF v_version<>2 THEN RAISE EXCEPTION 'FEJL: record placement version blev ikke 2'; END IF;
    SELECT red_decide_source_persona_placement(v_persona_placement,1,'accepted','{"basis":"review"}') INTO v_version;
    IF v_version<>2 THEN RAISE EXCEPTION 'FEJL: persona placement version blev ikke 2'; END IF;
    v_error:=NULL;
    BEGIN
      PERFORM red_decide_source_persona_placement(v_persona_placement,1,'superseded','{"basis":"stale"}');
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_PLACEMENT_VERSION_CONFLICT%' THEN
      RAISE EXCEPTION 'FEJL: stale placement-version blev ikke afvist: %',v_error;
    END IF;
    SELECT red_decide_source_persona_placement(v_persona_placement,2,'superseded','{"basis":"replacement"}') INTO v_version;
    SELECT red_decide_source_record_placement(v_placement,2,'superseded','{"basis":"replacement"}') INTO v_version;
    RESET ROLE;
    INSERT INTO private.source_record_placement(source_record_id,scheme_entry_id,header_observation_id)
      VALUES (v_record_a,v_entry_a,v_observation_a) RETURNING id INTO v_rejected_placement;
    INSERT INTO private.source_record_placement_decision(
      placement_id,version,decision_status,evidence,decision_origin,decided_by_name
    ) VALUES (v_rejected_placement,1,'proposed','{"basis":"verify rejection"}','ingest','verify ingest');
    SET LOCAL ROLE authenticated;
    PERFORM red_decide_source_record_placement(v_rejected_placement,1,'rejected','{"basis":"review"}');
    v_error:=NULL;
    BEGIN
      PERFORM red_decide_source_record_placement(v_rejected_placement,2,'accepted','{"basis":"reopen"}');
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_PLACEMENT_TRANSITION_INVALID%' THEN
      RAISE EXCEPTION 'FEJL: rejected placement kunne genåbnes: %',v_error;
    END IF;
    RESET ROLE;
    RAISE EXCEPTION 'ROLLBACK_SLÆGT_VERIFY';
  EXCEPTION WHEN others THEN
    IF SQLERRM='ROLLBACK_SLÆGT_VERIFY' THEN
      RAISE NOTICE 'OK: slægt, lineage og kildeschemes er adskilt og context-scopede';
    ELSE
      RAISE;
    END IF;
  END;
END $slaegt_verify$;

-- ===== Evidensimport Fase 3 / Task 8: generelle beskrivelser og heraldik =====
DO $entity_description_verify$
DECLARE
  v_description bigint;
  v_slaegt bigint;
  v_error text;
BEGIN
  IF to_regclass('public.entity_description') IS NULL
     OR to_regclass('private.entity_description_source') IS NULL THEN
    RAISE EXCEPTION 'FEJL: Task 8 mangler entity_description-laget';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.entity_description'::regclass)
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private.entity_description_source'::regclass) THEN
    RAISE EXCEPTION 'FEJL: entity_description-laget mangler RLS';
  END IF;
  IF has_table_privilege('anon','private.entity_description_source','SELECT')
     OR has_table_privilege('authenticated','private.entity_description_source','SELECT') THEN
    RAISE EXCEPTION 'FEJL: private kilde-junction er direkte API-læsbar';
  END IF;
  BEGIN
    INSERT INTO public.slaegt(navn,sorteringsnavn,slug,status)
      VALUES ('Verify description clan','Verify description clan','verify-description-clan','active')
      RETURNING id INTO v_slaegt;
    INSERT INTO public.entity_description(subjekt_type,subjekt_id,kind,tekst,status)
      VALUES ('slaegt',v_slaegt,'overview','Redaktionel oversigt','published')
      RETURNING id INTO v_description;
    IF v_description IS NULL THEN RAISE EXCEPTION 'FEJL: kunne ikke oprette slægtsbeskrivelse'; END IF;
    v_error:=NULL;
    BEGIN
      INSERT INTO public.entity_description(subjekt_type,subjekt_id,kind,tekst,status)
        VALUES ('ukendt_type',v_slaegt,'overview','Må ikke findes','draft');
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    IF v_error NOT LIKE '%ENTITY_DESCRIPTION_SUBJECT_INVALID%' THEN
      RAISE EXCEPTION 'FEJL: ukendt beskrivelsesemne blev ikke afvist: %',v_error;
    END IF;
    RAISE EXCEPTION 'ROLLBACK_ENTITY_DESCRIPTION_VERIFY';
  EXCEPTION WHEN others THEN
    IF SQLERRM='ROLLBACK_ENTITY_DESCRIPTION_VERIFY' THEN
      RAISE NOTICE 'OK: entity descriptions er generelle, RLS-beskyttede og target-validerede';
    ELSE RAISE;
    END IF;
  END;
END $entity_description_verify$;

-- ===== Evidensimport Fase 2 / Task 5: fortolkning, promotion og identitet =====
DO $interpretation_verify$
DECLARE
  v_required text[] := ARRAY[
    'interpretation','interpretation_observation','interpretation_promotion',
    'source_persona_identity','source_persona_identity_event'
  ];
  v_missing text[];
  v_actor uuid := '11000000-0000-0000-0000-000000000021';
  v_member uuid := '11000000-0000-0000-0000-000000000022';
  v_run uuid := '22000000-0000-0000-0000-000000000021';
  v_rendition uuid := '33000000-0000-0000-0000-000000000021';
  v_occurrence uuid := '55000000-0000-0000-0000-000000000021';
  v_observation uuid := '66000000-0000-0000-0000-000000000021';
  v_mention uuid := '77000000-0000-0000-0000-000000000021';
  v_persona uuid := '88000000-0000-0000-0000-000000000021';
  v_interpretation uuid := 'c1000000-0000-0000-0000-000000000021';
  v_accepted_interpretation uuid;
  v_terminal_proposal uuid;
  v_terminal_decision uuid;
  v_terminal_status text;
  v_error text;
BEGIN
  SELECT array_agg(required_name ORDER BY required_name) INTO v_missing
    FROM unnest(v_required) AS required_name
   WHERE to_regclass(format('private.%I',required_name)) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: fortolkningslag mangler tabeller: %',v_missing;
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='private' AND c.relname=ANY(v_required) AND NOT c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'FEJL: mindst én privat fortolknings-/identitetstabel mangler RLS';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(v_required) AS required_name
     WHERE has_table_privilege('anon',format('private.%I',required_name),'SELECT')
        OR has_table_privilege('authenticated',format('private.%I',required_name),'SELECT')
        OR has_table_privilege('authenticated',format('private.%I',required_name),'INSERT')
        OR has_table_privilege('authenticated',format('private.%I',required_name),'UPDATE')
  ) OR has_table_privilege('anon','private.interpretation_current','SELECT')
     OR has_table_privilege('authenticated','private.interpretation_current','SELECT') THEN
    RAISE EXCEPTION 'FEJL: fortolknings-/identitetslaget har direkte API-rettigheder';
  END IF;
  IF to_regprocedure(
       'public.red_decide_interpretation(uuid,integer,text,jsonb)'
     ) IS NULL
     OR to_regprocedure(
       'public.red_promote_interpretation(uuid,text,bigint,jsonb)'
     ) IS NULL
     OR to_regprocedure(
       'private.decide_source_persona_identity(uuid,bigint,integer,text,jsonb,text)'
     ) IS NULL THEN
    RAISE EXCEPTION 'FEJL: fortolkningslaget mangler atomiske redaktions-RPCer';
  END IF;
  -- Trin 5a (#151): den offentlige identitetskerne må ikke findes; den private har ingen klientgrants.
  IF to_regprocedure('public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb)') IS NOT NULL
     OR to_regprocedure('public.red_afgoer_source_persona(uuid,integer,text,bigint,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: #151 den offentlige identitetskerne eller femarguments-wrapperen findes stadig';
  END IF;
  IF has_function_privilege('authenticated','private.decide_source_persona_identity(uuid,bigint,integer,text,jsonb,text)','EXECUTE')
     OR has_function_privilege('anon','private.decide_source_persona_identity(uuid,bigint,integer,text,jsonb,text)','EXECUTE') THEN
    RAISE EXCEPTION 'FEJL: #151 klientroller kan kalde den private identitetskerne';
  END IF;
  IF has_function_privilege(
       'anon','public.red_decide_interpretation(uuid,integer,text,jsonb)','EXECUTE'
     ) OR has_function_privilege(
       'anon','public.red_promote_interpretation(uuid,text,bigint,jsonb)','EXECUTE'
     ) THEN
    RAISE EXCEPTION 'FEJL: anon kan kalde fortolknings-/identitetsmutationer';
  END IF;

  BEGIN
    INSERT INTO auth.users(id,email) VALUES
      (v_actor,'interpretation-editor@test.invalid'),
      (v_member,'interpretation-member@test.invalid');
    INSERT INTO person(id,levende,privat,status) VALUES
      (-987650021,false,false,'verify identity A'),
      (-987650022,false,false,'verify identity B');
    INSERT INTO profiles(id,rolle,email,navn) VALUES
      (v_actor,'redaktion','interpretation-editor@test.invalid','Verify Editor'),
      (v_member,'medlem','interpretation-member@test.invalid','Verify Member');
    INSERT INTO source(id,titel,import_key)
      VALUES (-987650021,'Fortolkning verify','verify:interpretation');
    INSERT INTO private.extraction_run(
      id,source_id,run_key,schema_version,extractor_version,profile_version,
      input_sha256,manifest
    ) VALUES (
      v_run,-987650021,'interpretation-run','1.0','verify','verify',
      repeat('1',64),'{}'
    );
    INSERT INTO private.source_rendition(
      id,source_id,rendition_key,rendition_kind,content_sha256,metadata
    ) VALUES (
      v_rendition,-987650021,'interpretation-rendition','text_layer',
      repeat('2',64),'{}'
    );
    INSERT INTO private.source_record_occurrence(
      id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
      verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id
    ) VALUES (
      v_occurrence,v_rendition,'interpretation-occurrence',1,1,0,12,
      'Anna døde 1','physical-interpretation','structural-interpretation',v_run
    );
    INSERT INTO private.source_observation(
      id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
      verbatim_text,quality_status,extraction_method,extraction_run_id
    ) VALUES (
      v_observation,v_occurrence,'death_clause',1,1,0,12,'Anna døde 1',
      'clear','verify',v_run
    );
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
      VALUES (v_persona,-987650021,'interpretation-persona',v_run);

    -- En fortolkning må aldrig eksistere uden mindst én bærende observation.
    v_error := NULL;
    BEGIN
      INSERT INTO private.interpretation(
        id,interpretation_key,version,source_id,source_persona_id,
        interpretation_kind,predicate,value,schema_version,derivation_kind,
        confidence,status,method,extraction_run_id
      ) VALUES (
        'c1000000-0000-0000-0000-000000000020',
        'c0000000-0000-0000-0000-000000000020',1,-987650021,v_persona,
        'property','verify.death_date','{"raw":"1"}','1.0','source_statement',
        1,'proposed','verify',v_run
      );
      SET CONSTRAINTS private.interpretation_has_observation IMMEDIATE;
    EXCEPTION WHEN others THEN v_error := SQLERRM; END;
    SET CONSTRAINTS private.interpretation_has_observation DEFERRED;
    IF v_error NOT LIKE 'EVIDENCE_INTERPRETATION_OBSERVATION_REQUIRED%' THEN
      RAISE EXCEPTION 'FEJL: fortolkning uden observation blev ikke afvist: %',v_error;
    END IF;

    INSERT INTO private.interpretation(
      id,interpretation_key,version,source_id,source_persona_id,
      interpretation_kind,predicate,value,schema_version,derivation_kind,
      confidence,status,method,extraction_run_id
    ) VALUES (
      v_interpretation,'c0000000-0000-0000-0000-000000000021',1,
      -987650021,v_persona,'property','verify.death_date','{"raw":"1"}','1.0',
      'source_statement',1,'proposed','verify',v_run
    );
    INSERT INTO private.interpretation_observation(
      interpretation_id,observation_id,evidence_role,ordinal
    ) VALUES (v_interpretation,v_observation,'supporting',1);
    SET CONSTRAINTS private.interpretation_has_observation IMMEDIATE;
    SET CONSTRAINTS private.interpretation_has_observation DEFERRED;

    -- Direkte promotion af et forslag er fail-closed.
    v_error := NULL;
    BEGIN
      INSERT INTO private.interpretation_promotion(
        interpretation_id,target_type,target_id,evidence,
        promoted_by,promoted_by_name
      ) VALUES (
        v_interpretation,'person',-987650021,'{"basis":"invalid"}',
        v_actor,'Verify Editor'
      );
    EXCEPTION WHEN others THEN v_error := SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_INTERPRETATION_NOT_ACCEPTED%' THEN
      RAISE EXCEPTION 'FEJL: promotion uden accepted fortolkning blev ikke afvist: %',v_error;
    END IF;

    -- Et importpayload kan ikke selv erklære sig menneskeligt godkendt.
    PERFORM set_config('request.jwt.claim.sub',v_member::text,true);
    v_error := NULL;
    BEGIN
      PERFORM red_decide_interpretation(
        v_interpretation,1,'accepted','{"basis":"fake human"}'
      );
    EXCEPTION WHEN others THEN v_error := SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_ROLE_FORBIDDEN%' THEN
      RAISE EXCEPTION 'FEJL: medlem kunne fremstille menneskelig godkendelse: %',v_error;
    END IF;

    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    v_error:=NULL;
    BEGIN
      PERFORM private.decide_source_persona_identity(v_persona,-987650021,0,'accepted','{"basis":"web_detail","note":"direct without mention"}','human');
      RAISE EXCEPTION 'IDENTITY_WITHOUT_MENTION_BYPASS';
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_PERSONA_BASIS_REQUIRED%' THEN
      RAISE EXCEPTION 'FEJL: direkte accepted uden mention blev ikke afvist: %',v_error;
    END IF;
    v_error:=NULL;
    BEGIN
      PERFORM private.decide_source_persona_identity(v_persona,-987650021,0,'rejected','{"basis":"web_detail","note":"direct invalid target"}','human');
      RAISE EXCEPTION 'IDENTITY_REJECTED_TARGET_BYPASS';
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_IDENTITY_DECISION_INVALID%' THEN
      RAISE EXCEPTION 'FEJL: direkte rejected med target blev ikke afvist: %',v_error;
    END IF;
    INSERT INTO private.source_mention(
      id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id
    ) VALUES (v_mention,v_observation,'person',0,4,'Anna',v_run);
    INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
      VALUES (v_persona,v_mention,'principal',1);
    v_error:=NULL;
    BEGIN
      PERFORM red_decide_interpretation(
        v_interpretation,NULL,'accepted','{"basis":"null version"}'
      );
      RAISE EXCEPTION 'NULL_VERSION_BYPASS';
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_EXPECTED_VERSION_REQUIRED%' THEN
      RAISE EXCEPTION 'FEJL: NULL expected_version bypassede fortolkningslåsen: %',v_error;
    END IF;

    -- Selv hvis ingestrollen senere får INSERT til proposal-loading, må den
    -- ikke kunne forfalske en menneskelig afgørelse uden om RPC'en.
    GRANT USAGE ON SCHEMA private TO service_role;
    GRANT INSERT ON private.interpretation,
                    private.interpretation_promotion,
                    private.source_persona_identity_event
      TO service_role;
    ALTER ROLE service_role BYPASSRLS;
    v_error:=NULL;
    BEGIN
      SET LOCAL ROLE service_role;
      INSERT INTO private.interpretation(
        id,interpretation_key,version,source_id,source_persona_id,
        interpretation_kind,predicate,value,schema_version,derivation_kind,
        confidence,status,method,extraction_run_id,decision_evidence,
        decided_by,decided_by_name,decided_at
      ) VALUES (
        'c1000000-0000-0000-0000-000000000029',
        'c0000000-0000-0000-0000-000000000029',1,-987650021,v_persona,
        'property','verify.fake_approval','{}','1.0','human_judgement',1,'accepted',
        'forged',v_run,'{"basis":"forged"}',v_actor,'Forged',clock_timestamp()
      );
      RAISE EXCEPTION 'SERVICE_ROLE_FAKE_ACCEPTED';
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_DECISION_PROVENANCE_REQUIRED%' THEN
      RAISE EXCEPTION 'FEJL: ingestrolle kunne skrive falsk accepted fortolkning: %',v_error;
    END IF;

    SELECT red_decide_interpretation(
      v_interpretation,1,'accepted','{"basis":"reviewed"}'
    ) INTO v_accepted_interpretation;
    IF NOT EXISTS (
      SELECT 1 FROM private.interpretation_current
       WHERE interpretation_key='c0000000-0000-0000-0000-000000000021'
         AND id=v_accepted_interpretation AND status='accepted' AND version=2
         AND decided_by=v_actor AND decided_by_name='Verify Editor'
    ) THEN
      RAISE EXCEPTION 'FEJL: accepted fortolkning mangler versions-/aktøraudit';
    END IF;
    v_error:=NULL;
    BEGIN
      PERFORM red_decide_interpretation(
        v_accepted_interpretation,2,'rejected','{"basis":"second decision"}'
      );
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    IF v_error IS NULL OR v_error NOT LIKE 'EVIDENCE_INTERPRETATION_NOT_PROPOSED%' THEN
      RAISE EXCEPTION 'FEJL: accepted fortolkning kunne afgøres igen: %',v_error;
    END IF;
    IF (SELECT count(*) FROM private.interpretation
         WHERE interpretation_key='c0000000-0000-0000-0000-000000000021')<>2 THEN
      RAISE EXCEPTION 'FEJL: second decision oprettede en ekstra fortolkningsversion';
    END IF;
    FOREACH v_terminal_status IN ARRAY ARRAY['rejected','unresolved','superseded'] LOOP
      v_terminal_proposal:=gen_random_uuid();
      INSERT INTO private.interpretation(
        id,interpretation_key,version,source_id,source_persona_id,
        interpretation_kind,predicate,value,schema_version,derivation_kind,
        confidence,status,method,extraction_run_id
      ) VALUES (
        v_terminal_proposal,gen_random_uuid(),1,-987650021,v_persona,
        'property','verify.terminal_status','{}','1.0','source_statement',1,
        'proposed','verify',v_run
      );
      INSERT INTO private.interpretation_observation(
        interpretation_id,observation_id,evidence_role,ordinal
      ) VALUES (v_terminal_proposal,v_observation,'supporting',1);
      SELECT red_decide_interpretation(
        v_terminal_proposal,1,v_terminal_status,'{"basis":"terminal state verify"}'
      ) INTO v_terminal_decision;
      IF NOT EXISTS (
        SELECT 1 FROM private.interpretation
         WHERE id=v_terminal_decision AND version=2 AND status=v_terminal_status
      ) THEN
        RAISE EXCEPTION 'FEJL: terminal fortolkningsstatus % blev ikke skrevet append-only',v_terminal_status;
      END IF;
      v_error:=NULL;
      BEGIN
        PERFORM red_decide_interpretation(
          v_terminal_decision,2,'accepted','{"basis":"invalid terminal redecision"}'
        );
      EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
      IF v_error IS NULL OR v_error NOT LIKE 'EVIDENCE_INTERPRETATION_NOT_PROPOSED%' THEN
        RAISE EXCEPTION 'FEJL: terminal fortolkning % kunne afgøres igen: %',v_terminal_status,v_error;
      END IF;
    END LOOP;
    PERFORM red_promote_interpretation(
      v_accepted_interpretation,'person',-987650021,'{"basis":"verified"}'
    );
    v_error:=NULL;
    BEGIN
      SET LOCAL ROLE service_role;
      INSERT INTO private.interpretation_promotion(
        interpretation_id,target_type,target_id,evidence,promoted_by,promoted_by_name
      ) VALUES (
        v_accepted_interpretation,'person',-987650022,'{"basis":"forged"}',
        v_actor,'Forged'
      );
      RAISE EXCEPTION 'SERVICE_ROLE_FAKE_PROMOTION';
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_DECISION_PROVENANCE_REQUIRED%' THEN
      RAISE EXCEPTION 'FEJL: ingestrolle kunne skrive falsk promotion: %',v_error;
    END IF;
    v_error:=NULL;
    BEGIN
      UPDATE private.interpretation SET predicate='rewritten'
       WHERE id=v_accepted_interpretation;
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_APPEND_ONLY%' THEN
      RAISE EXCEPTION 'FEJL: accepteret fortolkning kunne overskrives: %',v_error;
    END IF;

    -- En accepteret identitetsafgørelse uden aktørmetadata afvises selv ved
    -- direkte ejer-write; almindelige roller har slet ingen tabeladgang.
    v_error := NULL;
    BEGIN
      INSERT INTO private.source_persona_identity_event(
        source_persona_id,canonical_person_id,decision_status,version,evidence
      ) VALUES (
        v_persona,-987650021,'accepted',1,'{"basis":"missing actor"}'
      );
    EXCEPTION WHEN others THEN v_error := SQLERRM; END;
    IF v_error IS NULL THEN
      RAISE EXCEPTION 'FEJL: identitetsafgørelse uden actor/tid blev accepteret';
    END IF;
    v_error:=NULL;
    BEGIN
      SET LOCAL ROLE service_role;
      INSERT INTO private.source_persona_identity_event(
        source_persona_id,canonical_person_id,decision_status,version,evidence,
        decided_by,decided_by_name,decided_at
      ) VALUES (
        v_persona,-987650021,'accepted',1,'{"basis":"forged"}',
        v_actor,'Forged',clock_timestamp()
      );
      RAISE EXCEPTION 'SERVICE_ROLE_FAKE_IDENTITY';
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_DECISION_PROVENANCE_REQUIRED%' THEN
      RAISE EXCEPTION 'FEJL: ingestrolle kunne skrive falsk identitetsafgørelse: %',v_error;
    END IF;

    v_error := NULL;
    BEGIN
      INSERT INTO private.source_persona_identity(
        source_persona_id,canonical_person_id,decision_status,version,evidence
      ) VALUES (v_persona,NULL,'proposed',1,'{}');
      SET CONSTRAINTS private.identity_state_has_event IMMEDIATE;
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    SET CONSTRAINTS private.identity_state_has_event DEFERRED;
    IF v_error NOT LIKE 'EVIDENCE_IDENTITY_EVENT_REQUIRED%' THEN
      RAISE EXCEPTION 'FEJL: identity-state uden event blev ikke afvist: %',v_error;
    END IF;

    v_error:=NULL;
    BEGIN
      PERFORM private.decide_source_persona_identity(v_persona,-987650021,NULL,'accepted','{"basis":"web_detail","note":"null version"}','human');
      RAISE EXCEPTION 'NULL_VERSION_BYPASS';
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_EXPECTED_VERSION_REQUIRED%' THEN
      RAISE EXCEPTION 'FEJL: NULL expected_version bypassede identity-låsen: %',v_error;
    END IF;

    PERFORM private.decide_source_persona_identity(v_persona,-987650021,0,'accepted','{"basis":"web_detail","note":"reviewed"}','human');
    IF (SELECT count(*) FROM private.source_persona_identity
         WHERE source_persona_id=v_persona AND decision_status='accepted')<>1
       OR NOT EXISTS (
         SELECT 1 FROM private.source_persona_identity
          WHERE source_persona_id=v_persona AND canonical_person_id=-987650021
            AND version=1 AND decided_by=v_actor
       ) THEN
      RAISE EXCEPTION 'FEJL: persona fik ikke præcis ét aktivt kanonisk mål';
    END IF;
    v_error:=NULL;
    BEGIN
      UPDATE private.source_persona_identity_event SET evidence='{"rewritten":true}'
       WHERE source_persona_id=v_persona AND version=1;
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_APPEND_ONLY%' THEN
      RAISE EXCEPTION 'FEJL: identity-event kunne overskrives: %',v_error;
    END IF;

    v_error := NULL;
    BEGIN
      PERFORM private.decide_source_persona_identity(v_persona,-987650022,0,'accepted','{"basis":"web_detail","note":"stale"}','human');
    EXCEPTION WHEN others THEN v_error := SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_IDENTITY_VERSION_CONFLICT%' THEN
      RAISE EXCEPTION 'FEJL: stale identitetsafgørelse blev ikke afvist: %',v_error;
    END IF;

    PERFORM private.decide_source_persona_identity(v_persona,-987650022,1,'accepted','{"basis":"web_detail","note":"revised review"}','human');
    v_error:=NULL;
    BEGIN
      UPDATE private.source_persona_identity state SET
        canonical_person_id=event.canonical_person_id,
        decision_status=event.decision_status,
        version=event.version,
        evidence=event.evidence,
        decided_by=event.decided_by,
        decided_by_name=event.decided_by_name,
        decided_at=event.decided_at
      FROM private.source_persona_identity_event event
      WHERE state.source_persona_id=v_persona
        AND event.source_persona_id=v_persona AND event.version=1;
      SET CONSTRAINTS private.identity_state_has_event IMMEDIATE;
      RAISE EXCEPTION 'IDENTITY_REWIND_BYPASS';
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    SET CONSTRAINTS private.identity_state_has_event DEFERRED;
    IF v_error NOT LIKE 'EVIDENCE_IDENTITY_LATEST_REQUIRED%' THEN
      RAISE EXCEPTION 'FEJL: current identity kunne rewindes til historisk event: %',v_error;
    END IF;
    v_error:=NULL;
    BEGIN
      DELETE FROM private.source_persona_identity WHERE source_persona_id=v_persona;
      SET CONSTRAINTS private.identity_state_has_event IMMEDIATE;
      RAISE EXCEPTION 'IDENTITY_DELETE_BYPASS';
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    SET CONSTRAINTS private.identity_state_has_event DEFERRED;
    IF v_error NOT LIKE 'EVIDENCE_IDENTITY_STATE_REQUIRED%' THEN
      RAISE EXCEPTION 'FEJL: current identity kunne slettes med eventhistorik: %',v_error;
    END IF;

    RAISE EXCEPTION 'ROLLBACK_INTERPRETATION_VERIFY';
  EXCEPTION WHEN others THEN
    IF SQLERRM='ROLLBACK_INTERPRETATION_VERIFY' THEN
      RAISE NOTICE 'OK: fortolkning, promotion og identitet er private, auditerede og fail-closed';
    ELSE
      RAISE;
    END IF;
  END;
END $interpretation_verify$;

-- To samtidige afgørelser af samme proposal skal serialiseres; den tabende
-- transaktion må ikke skabe en tredje version efter den første commit.
DO $interpretation_concurrency$
DECLARE
  v_conn text := format(
    'dbname=%s port=%s host=%s',current_database(),current_setting('port'),
    split_part(current_setting('unix_socket_directories'),',',1)
  );
  v_actor uuid := '11000000-0000-0000-0000-000000000061';
  v_run uuid := '22000000-0000-0000-0000-000000000061';
  v_rendition uuid := '33000000-0000-0000-0000-000000000061';
  v_occurrence uuid := '55000000-0000-0000-0000-000000000061';
  v_observation uuid := '66000000-0000-0000-0000-000000000061';
  v_persona uuid := '88000000-0000-0000-0000-000000000061';
  v_interpretation uuid := 'c1000000-0000-0000-0000-000000000061';
  v_a_pid integer;
  v_b_pid integer;
  v_busy integer;
  v_deadline timestamptz;
  v_error text;
  v_setup_connected boolean := false;
  v_a_connected boolean := false;
  v_b_connected boolean := false;
  v_cleanup text := $cleanup$
    SET session_replication_role=replica;
    DELETE FROM private.interpretation_observation
     WHERE interpretation_id IN (
       SELECT id FROM private.interpretation
        WHERE interpretation_key='c0000000-0000-0000-0000-000000000061'
     );
    DELETE FROM private.interpretation
     WHERE interpretation_key='c0000000-0000-0000-0000-000000000061';
    DELETE FROM private.source_persona WHERE id='88000000-0000-0000-0000-000000000061';
    DELETE FROM private.source_observation WHERE id='66000000-0000-0000-0000-000000000061';
    DELETE FROM private.source_record_occurrence WHERE id='55000000-0000-0000-0000-000000000061';
    DELETE FROM private.source_rendition WHERE id='33000000-0000-0000-0000-000000000061';
    DELETE FROM private.extraction_run WHERE id='22000000-0000-0000-0000-000000000061';
    DELETE FROM source WHERE id=-987650061;
    DELETE FROM profiles WHERE id='11000000-0000-0000-0000-000000000061';
    DELETE FROM auth.users WHERE id='11000000-0000-0000-0000-000000000061';
    SET session_replication_role=origin;
  $cleanup$;
BEGIN
  IF to_regprocedure('dblink_connect(text,text)') IS NULL THEN
    RAISE EXCEPTION 'DB_VERIFY_DBLINK_REQUIRED: fortolkningssamtidighed';
  END IF;
  PERFORM dblink_connect('interpretation_setup',v_conn||' application_name=daa_verify_interpretation_setup');
  v_setup_connected:=true;
  PERFORM dblink_exec('interpretation_setup',v_cleanup);
  PERFORM dblink_exec('interpretation_setup',format(
    'INSERT INTO auth.users(id,email) VALUES (''%s'',''interpretation-lock@test.invalid'')',v_actor));
  PERFORM dblink_exec('interpretation_setup',format(
    'INSERT INTO profiles(id,rolle,email,navn) VALUES (''%s'',''redaktion'',''interpretation-lock@test.invalid'',''Interpretation Editor'')',v_actor));
  PERFORM dblink_exec('interpretation_setup',
    'INSERT INTO source(id,titel,import_key) VALUES (-987650061,''Interpretation lock'',''verify:interpretation:lock'')');
  PERFORM dblink_exec('interpretation_setup',
    'INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) '
    || 'VALUES (''22000000-0000-0000-0000-000000000061'',-987650061,''interpretation-lock-run'',''1.0'',''verify'',''verify'','
    || quote_literal(repeat('6',64)) || ',''{}'')');
  PERFORM dblink_exec('interpretation_setup',
    'INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata) '
    || 'VALUES (''33000000-0000-0000-0000-000000000061'',-987650061,''interpretation-lock-rendition'',''text_layer'','
    || quote_literal(repeat('7',64)) || ',''{}'')');
  PERFORM dblink_exec('interpretation_setup',
    'INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id) '
    || 'VALUES (''55000000-0000-0000-0000-000000000061'',''33000000-0000-0000-0000-000000000061'',''interpretation-lock-occurrence'',1,1,0,4,''Anna'',''interpretation-physical'',''interpretation-structural'',''22000000-0000-0000-0000-000000000061'')');
  PERFORM dblink_exec('interpretation_setup',
    'INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id) '
    || 'VALUES (''66000000-0000-0000-0000-000000000061'',''55000000-0000-0000-0000-000000000061'',''name'',1,1,0,4,''Anna'',''clear'',''verify'',''22000000-0000-0000-0000-000000000061'')');
  PERFORM dblink_exec('interpretation_setup',
    'INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) '
    || 'VALUES (''88000000-0000-0000-0000-000000000061'',-987650061,''interpretation-lock-persona'',''22000000-0000-0000-0000-000000000061'')');
  PERFORM dblink_exec('interpretation_setup','BEGIN');
  PERFORM dblink_exec('interpretation_setup','SET CONSTRAINTS ALL DEFERRED');
  PERFORM dblink_exec('interpretation_setup',
    'INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id) '
    || 'VALUES (''c1000000-0000-0000-0000-000000000061'',''c0000000-0000-0000-0000-000000000061'',1,-987650061,''88000000-0000-0000-0000-000000000061'',''property'',''verify.name'',''{}'',''1.0'',''source_statement'',1,''proposed'',''verify'',''22000000-0000-0000-0000-000000000061'')');
  PERFORM dblink_exec('interpretation_setup',
    'INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal) VALUES (''c1000000-0000-0000-0000-000000000061'',''66000000-0000-0000-0000-000000000061'',''supporting'',1)');
  PERFORM dblink_exec('interpretation_setup','COMMIT');
  PERFORM dblink_connect('interpretation_a',v_conn||' application_name=daa_verify_interpretation_a');
  v_a_connected:=true;
  PERFORM dblink_connect('interpretation_b',v_conn||' application_name=daa_verify_interpretation_b');
  v_b_connected:=true;
  SELECT pid INTO v_a_pid FROM dblink('interpretation_a','SELECT pg_backend_pid()') AS t(pid integer);
  SELECT pid INTO v_b_pid FROM dblink('interpretation_b','SELECT pg_backend_pid()') AS t(pid integer);
  PERFORM dblink_exec('interpretation_a','BEGIN');
  PERFORM dblink_exec('interpretation_a','SET LOCAL ROLE authenticated');
  PERFORM dblink_exec('interpretation_a',format('SET LOCAL "request.jwt.claim.sub"=%L',v_actor::text));
  PERFORM * FROM dblink('interpretation_a',format(
    'SELECT red_decide_interpretation(''%s'',1,''accepted'',''{"basis":"A"}'')',v_interpretation
  )) AS t(decision_id uuid);
  PERFORM dblink_exec('interpretation_b','BEGIN');
  PERFORM dblink_exec('interpretation_b','SET LOCAL ROLE authenticated');
  PERFORM dblink_exec('interpretation_b',format('SET LOCAL "request.jwt.claim.sub"=%L',v_actor::text));
  PERFORM dblink_send_query('interpretation_b',format(
    'SELECT red_decide_interpretation(''%s'',1,''rejected'',''{"basis":"B"}'')',v_interpretation
  ));
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP
    EXIT WHEN v_a_pid=ANY(pg_blocking_pids(v_b_pid));
    SELECT dblink_is_busy('interpretation_b') INTO v_busy;
    IF v_busy=0 OR clock_timestamp()>v_deadline THEN
      RAISE EXCEPTION 'FEJL: fortolkningsafgørelse B ventede ikke på proposal-låsen';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  PERFORM dblink_exec('interpretation_a','COMMIT');
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP
    SELECT dblink_is_busy('interpretation_b') INTO v_busy;
    EXIT WHEN v_busy=0;
    IF clock_timestamp()>v_deadline THEN
      RAISE EXCEPTION 'FEJL: fortolkningsafgørelse B afsluttede ikke';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  v_error:=NULL;
  BEGIN
    PERFORM * FROM dblink_get_result('interpretation_b') AS t(decision_id uuid);
  EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
  BEGIN
    PERFORM * FROM dblink_get_result('interpretation_b') AS t(decision_id uuid);
  EXCEPTION WHEN others THEN IF v_error IS NULL THEN v_error:=SQLERRM; END IF; END;
  IF v_error NOT LIKE '%EVIDENCE_INTERPRETATION_VERSION_CONFLICT%' THEN
    RAISE EXCEPTION 'FEJL: tabende fortolkningsafgørelse fejlede ikke fail-closed: %',v_error;
  END IF;
  PERFORM dblink_exec('interpretation_b','ROLLBACK');
  IF (SELECT count(*) FROM private.interpretation
       WHERE interpretation_key='c0000000-0000-0000-0000-000000000061')<>2 THEN
    RAISE EXCEPTION 'FEJL: fortolknings-race efterlod mere end én decision-version';
  END IF;
  PERFORM dblink_disconnect('interpretation_a'); v_a_connected:=false;
  PERFORM dblink_disconnect('interpretation_b'); v_b_connected:=false;
  PERFORM dblink_exec('interpretation_setup',v_cleanup);
  PERFORM dblink_disconnect('interpretation_setup'); v_setup_connected:=false;
  PERFORM set_config('daa.verify_dblink_interpretation','executed',false);
  RAISE NOTICE 'OK: fortolkningsafgørelser serialiseres og taberen skriver ingen ny version';
EXCEPTION WHEN others THEN
  IF v_a_connected THEN
    BEGIN PERFORM dblink_exec('interpretation_a','ROLLBACK'); EXCEPTION WHEN others THEN NULL; END;
    BEGIN PERFORM dblink_disconnect('interpretation_a'); EXCEPTION WHEN others THEN NULL; END;
  END IF;
  IF v_b_connected THEN
    BEGIN PERFORM dblink_exec('interpretation_b','ROLLBACK'); EXCEPTION WHEN others THEN NULL; END;
    BEGIN PERFORM dblink_disconnect('interpretation_b'); EXCEPTION WHEN others THEN NULL; END;
  END IF;
  IF v_setup_connected THEN
    BEGIN PERFORM dblink_exec('interpretation_setup',v_cleanup); EXCEPTION WHEN others THEN NULL; END;
    BEGIN PERFORM dblink_disconnect('interpretation_setup'); EXCEPTION WHEN others THEN NULL; END;
  END IF;
  RAISE;
END $interpretation_concurrency$;

-- ===== Evidensimport Fase 2 / Task 1: promotionregler og batch-audit =====
DO $promotion_rule_verify$
DECLARE
  v_required text[] := ARRAY[
    'interpretation_promotion_rule_line','interpretation_promotion_rule',
    'interpretation_promotion_batch'
  ];
  v_missing text[];
  v_error text;
  v_actor uuid := '11000000-0000-0000-0000-000000000041';
  v_run uuid := '22000000-0000-0000-0000-000000000041';
  v_rendition uuid := '33000000-0000-0000-0000-000000000041';
  v_occurrence uuid := '55000000-0000-0000-0000-000000000041';
  v_observation uuid := '66000000-0000-0000-0000-000000000041';
  v_header_observation uuid := '66000000-0000-0000-0000-000000000048';
  v_mention uuid := '70000000-0000-0000-0000-000000000041';
  v_persona uuid := '88000000-0000-0000-0000-000000000041';
  v_record uuid := '77000000-0000-0000-0000-000000000041';
  v_record_placement uuid := '99000000-0000-0000-0000-000000000041';
  v_spouse_placement uuid := '99000000-0000-0000-0000-000000000042';
  v_principal_placement uuid := '99000000-0000-0000-0000-000000000043';
  v_slaegt_id bigint;
  v_scheme_id bigint;
  v_scheme_entry_id bigint;
  v_interpretation_1 uuid := 'c1000000-0000-0000-0000-000000000041';
  v_interpretation_2 uuid := 'c1000000-0000-0000-0000-000000000042';
  v_interpretation_3 uuid := 'c1000000-0000-0000-0000-000000000043';
  v_interpretation_no_bulk_1 uuid := 'c1000000-0000-0000-0000-000000000044';
  v_interpretation_no_bulk_2 uuid := 'c1000000-0000-0000-0000-000000000045';
  v_interpretation_principal uuid := 'c1000000-0000-0000-0000-000000000046';
  v_interpretation_stale uuid := 'c1000000-0000-0000-0000-000000000047';
  v_accepted_1 uuid;
  v_accepted_2 uuid;
  v_accepted_3 uuid;
  v_accepted_no_bulk_1 uuid;
  v_accepted_no_bulk_2 uuid;
  v_accepted_principal uuid;
  v_accepted_stale uuid;
  v_preview jsonb;
  v_before_promotions integer;
  v_before_batches integer;
  v_before_persons integer;
  v_before_facts integer;
  v_before_assertions integer;
  v_rule_version integer;
BEGIN
  SELECT array_agg(required_name ORDER BY required_name) INTO v_missing
    FROM unnest(v_required) AS required_name
   WHERE to_regclass(format('private.%I',required_name)) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: promotionregel-laget mangler';
  END IF;
  IF to_regclass('private.interpretation_promotion_rule_current') IS NULL
     OR to_regprocedure('private.add_interpretation_promotion_rule_version(text,text,text,text,text,text,boolean,boolean,boolean,text)') IS NULL THEN
    RAISE EXCEPTION 'FEJL: promotionregel-laget mangler current-view/version-writer';
  END IF;
  IF EXISTS (
    SELECT 1
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='private' AND c.relname=ANY(v_required)
       AND (
         NOT c.relrowsecurity
         OR has_table_privilege('anon',c.oid,'SELECT')
         OR has_table_privilege('anon',c.oid,'INSERT')
         OR has_table_privilege('anon',c.oid,'UPDATE')
         OR has_table_privilege('anon',c.oid,'DELETE')
         OR has_table_privilege('authenticated',c.oid,'SELECT')
         OR has_table_privilege('authenticated',c.oid,'INSERT')
         OR has_table_privilege('authenticated',c.oid,'UPDATE')
         OR has_table_privilege('authenticated',c.oid,'DELETE')
         OR EXISTS (
           SELECT 1
             FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) acl
            WHERE acl.grantee=0
              AND acl.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')
         )
       )
  ) THEN
    RAISE EXCEPTION 'FEJL: promotionregel-laget har direkte API-rettigheder';
  END IF;
  IF EXISTS (
    SELECT 1
      FROM unnest(v_required) AS required_name
     WHERE (
       SELECT count(*)
         FROM pg_catalog.pg_trigger t
         JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
        WHERE NOT t.tgisinternal
          AND c.relnamespace='private'::regnamespace
          AND c.relname=required_name
          AND t.tgname='trg_'||c.relname||'_append_only'
          AND t.tgfoid='private.reject_evidence_mutation()'::regprocedure
          AND t.tgenabled='O'
     )<>1
  ) THEN
    RAISE EXCEPTION 'FEJL: promotionregel-laget mangler append-only-triggere';
  END IF;
  IF (
    SELECT count(*) FROM pg_catalog.pg_constraint c
     WHERE c.conrelid='private.interpretation_promotion'::regclass
       AND c.contype='f'
       AND c.confrelid='private.interpretation_promotion_rule'::regclass
  )<>1
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='private.interpretation_promotion'::regclass
          AND c.conname='interpretation_promotion_rule_fk'
     )
     OR (
       SELECT count(*) FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='private.interpretation_promotion'::regclass
          AND c.contype='f'
          AND c.confrelid='private.interpretation_promotion_batch'::regclass
     )<>1
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='private.interpretation_promotion'::regclass
          AND c.conname='interpretation_promotion_batch_fk'
     )
     OR (
       SELECT count(*) FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='private.interpretation_promotion'::regclass
          AND c.contype='c'
          AND position('rule_key IS NULL' IN pg_get_constraintdef(c.oid))>0
          AND position('rule_version IS NULL' IN pg_get_constraintdef(c.oid))>0
     )<>1
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='private.interpretation_promotion'::regclass
          AND c.conname='interpretation_promotion_rule_pair_check'
     ) THEN
    RAISE EXCEPTION 'FEJL: promotionregel-laget har ikke præcis én navngivet audit-constraint';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM private.interpretation_promotion_rule
        WHERE rule_key='person-name-v1' AND rule_version=1
          AND predicate='person.name' AND interpretation_kind='property'
          AND target_type='assertion' AND expected_fact_type='navn'
          AND value_kind='text' AND requires_persona_identity
          AND bulk_eligible AND status='active'
     )
     OR NOT EXISTS (
       SELECT 1 FROM private.interpretation_promotion_rule
        WHERE rule_key='person-byname-v1' AND rule_version=1
          AND predicate='person.byname' AND interpretation_kind='property'
          AND target_type='assertion' AND expected_fact_type='tilnavn'
          AND value_kind='text' AND requires_persona_identity
          AND bulk_eligible AND status='active'
     )
     OR NOT EXISTS (
       SELECT 1 FROM private.interpretation_promotion_rule
        WHERE rule_key='person-title-v1' AND rule_version=1
          AND predicate='person.title' AND interpretation_kind='property'
          AND target_type='assertion' AND expected_fact_type='titel'
          AND value_kind='text' AND requires_persona_identity
          AND bulk_eligible AND status='active'
     )
     OR NOT EXISTS (
       SELECT 1 FROM private.interpretation_promotion_rule
        WHERE rule_key='person-birth-v1' AND rule_version=1
          AND predicate='person.birth' AND interpretation_kind='property'
          AND target_type='assertion' AND expected_fact_type='fødsel'
          AND value_kind='date_raw' AND requires_persona_identity
          AND bulk_eligible AND status='active'
     )
     OR NOT EXISTS (
       SELECT 1 FROM private.interpretation_promotion_rule
        WHERE rule_key='person-death-v1' AND rule_version=1
          AND predicate='person.death' AND interpretation_kind='property'
          AND target_type='assertion' AND expected_fact_type='død'
          AND value_kind='date_raw' AND requires_persona_identity
          AND bulk_eligible AND status='active'
     ) THEN
    RAISE EXCEPTION 'FEJL: promotionregel-laget mangler';
  END IF;
  IF (
    SELECT count(*) FROM private.interpretation_promotion_rule
     WHERE rule_version=1 AND status='active'
  )<>5 THEN
    RAISE EXCEPTION 'FEJL: promotionregel-laget har ikke præcis fem aktive v1-regler';
  END IF;
  IF EXISTS (
    SELECT 1 FROM private.interpretation_promotion_rule
     WHERE rule_key='unknown-rule-v1' AND rule_version=1
  ) THEN
    RAISE EXCEPTION 'FEJL: ukendt promotionregel findes';
  END IF;
  v_error:=NULL;
  BEGIN
    INSERT INTO private.interpretation_promotion_rule_line(rule_key,predicate)
      VALUES ('verify-relation-target','person.name.relation');
    INSERT INTO private.interpretation_promotion_rule(
      rule_key,rule_version,predicate,interpretation_kind,target_type,expected_fact_type,
      value_kind,status
    ) VALUES (
      'verify-relation-target',1,'person.name.relation','property','relation','navn',
      'text','retired'
    );
  EXCEPTION WHEN others THEN v_error:=SQLERRM;
  END;
  IF v_error IS NULL THEN
    RAISE EXCEPTION 'FEJL: person.name må ikke promote til relation';
  END IF;
  v_error:=NULL;
  BEGIN
    UPDATE private.interpretation_promotion_rule
       SET status='retired'
     WHERE rule_key='person-name-v1' AND rule_version=1;
  EXCEPTION WHEN others THEN v_error:=SQLERRM;
  END;
  IF v_error NOT LIKE 'EVIDENCE_APPEND_ONLY%' THEN
    RAISE EXCEPTION 'FEJL: promotionregler er ikke append-only: %',v_error;
  END IF;
  v_error:=NULL;
  BEGIN
    INSERT INTO private.interpretation_promotion_batch(
      rule_profile_hash,preview_hash,promoted_by,promoted_by_name,requested_count
    ) VALUES (
      'verify-rule-profile','verify-preview',gen_random_uuid(),'Verify Editor',1
    );
    UPDATE private.interpretation_promotion_batch
       SET requested_count=2
     WHERE rule_profile_hash='verify-rule-profile';
  EXCEPTION WHEN others THEN v_error:=SQLERRM;
  END;
  IF v_error NOT LIKE 'EVIDENCE_APPEND_ONLY%' THEN
    RAISE EXCEPTION 'FEJL: promotionbatches er ikke append-only: %',v_error;
  END IF;

  -- Task 2-kontrakten er selvstændig og rulles helt tilbage. Den beviser
  -- både previewets fail-closed begrundelser og batchens all-or-nothing-write.
  IF to_regprocedure('public.red_preview_interpretation_promotions(jsonb)') IS NULL
     OR to_regprocedure('public.red_promote_interpretations_batch(jsonb,text)') IS NULL THEN
    RAISE EXCEPTION 'FEJL: promotion-preview/RPC mangler';
  END IF;
  IF has_function_privilege('anon','public.red_preview_interpretation_promotions(jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.red_promote_interpretations_batch(jsonb,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_preview_interpretation_promotions(jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_promote_interpretations_batch(jsonb,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.red_promote_interpretation(uuid,text,bigint,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated',
          'private.validate_interpretation_promotion_items(jsonb,boolean)','EXECUTE') THEN
    RAISE EXCEPTION 'FEJL: promotion-RPC/validator ACL er ikke fail-closed';
  END IF;
  BEGIN
    INSERT INTO auth.users(id,email)
      VALUES (v_actor,'promotion-verify-editor@test.invalid');
    INSERT INTO profiles(id,rolle,navn,email)
      VALUES (v_actor,'redaktion','Promotion Verify Editor',
              'promotion-verify-editor@test.invalid');
    INSERT INTO person(id,levende,privat,status) VALUES
      (-987650041,false,false,'promotion canonical'),
      (-987650042,false,false,'promotion forkert person');
    INSERT INTO source(id,titel,import_key)
      VALUES (-987650041,'Promotion verify','verify:promotion');
    INSERT INTO private.extraction_run(
      id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest
    ) VALUES (
      v_run,-987650041,'promotion-run','1.0','verify','verify',repeat('4',64),'{}'
    );
    INSERT INTO private.source_rendition(
      id,source_id,rendition_key,rendition_kind,content_sha256,metadata
    ) VALUES (
      v_rendition,-987650041,'promotion-rendition','text_layer',repeat('5',64),'{}'
    );
    INSERT INTO private.source_record_occurrence(
      id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
      verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id
    ) VALUES (
      v_occurrence,v_rendition,'promotion-occurrence',1,1,0,12,
      'Anna Verify', 'physical-promotion','structural-promotion',v_run
    );
    INSERT INTO private.source_observation(
      id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
      verbatim_text,quality_status,extraction_method,extraction_run_id
    ) VALUES (
      v_observation,v_occurrence,'name_clause',1,1,0,12,'Anna Verify',
      'clear','verify',v_run
    );
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
      VALUES (v_persona,-987650041,'promotion-persona',v_run);
    INSERT INTO private.source_observation(
      id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
      verbatim_text,quality_status,extraction_method,extraction_run_id
    ) VALUES (
      v_header_observation,v_occurrence,'header',1,1,0,12,'Anna Verify',
      'clear','verify',v_run
    );
    INSERT INTO private.source_mention(
      id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id
    ) VALUES (v_mention,v_observation,'person',0,4,'Anna',v_run);
    INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
      VALUES (v_persona,v_mention,'principal',1);
    INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
      VALUES (v_record,-987650041,'promotion-placement-record','family_record',v_run);
    INSERT INTO private.source_record_anchor_event(
      occurrence_id,source_record_id,decision_status,evidence,version,
      decided_by,decided_by_name
    ) VALUES (
      v_occurrence,v_record,'accepted','{"basis":"promotion verify"}',1,
      v_actor,'Promotion Verify Editor'
    );
    INSERT INTO slaegt(navn,sorteringsnavn,slug)
      VALUES ('Promotion Verify Family','promotion verify family','promotion-verify-family')
      RETURNING id INTO v_slaegt_id;
    INSERT INTO lineage_scheme(slaegt_id,source_id,kind,label)
      VALUES (v_slaegt_id,-987650041,'stamtavle','Promotion verify scheme')
      RETURNING id INTO v_scheme_id;
    INSERT INTO lineage_scheme_entry(scheme_id,slaegt_id,code,label,sort_order)
      VALUES (v_scheme_id,v_slaegt_id,'I','Promotion verify I',0)
      RETURNING id INTO v_scheme_entry_id;
    INSERT INTO private.source_record_placement(
      id,source_record_id,scheme_entry_id,header_observation_id,initial_status
    ) VALUES (
      v_record_placement,v_record,v_scheme_entry_id,v_header_observation,'accepted'
    );
    INSERT INTO private.source_record_placement_decision(
      placement_id,version,decision_status,evidence,decision_origin,decided_by_name
    ) VALUES (v_record_placement,1,'accepted','{"basis":"verify fixture"}',
              'migration','legacy placement backfill');
    -- En accepteret ægtefælleomtale er bevidst ikke en hovedplacering.
    INSERT INTO private.source_persona_placement(
      id,source_persona_id,record_placement_id,placement_role,basis_observation_id,initial_status
    ) VALUES (
      v_spouse_placement,v_persona,v_record_placement,'mentioned_spouse',v_observation,'accepted'
    );
    INSERT INTO private.source_persona_placement_decision(
      placement_id,version,decision_status,evidence,decision_origin,decided_by_name
    ) VALUES (v_spouse_placement,1,'accepted','{"basis":"verify fixture"}',
              'migration','legacy placement backfill');
    INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES
      (-987650041,'person',-987650041,'navn'),
      (-987650042,'person',-987650041,'titel'),
      (-987650043,'person',-987650041,'navn'),
      (-987650044,'person',-987650042,'navn');
    INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,calendar,uforanderlig) VALUES
      (-987650041,'fact',-987650041,'Anna Verify','gregoriansk',true),
      (-987650042,'fact',-987650042,'Anna Verify','gregoriansk',true),
      (-987650043,'fact',-987650043,'Anden tekst','gregoriansk',true),
      (-987650044,'fact',-987650044,'Anna Verify','gregoriansk',true);
    INSERT INTO private.interpretation_promotion_rule_line(rule_key,predicate) VALUES
      ('verify-name-no-bulk','verify.person.name.no_bulk'),
      ('verify-name-principal','verify.person.name.principal');
    INSERT INTO private.interpretation_promotion_rule(
      rule_key,rule_version,predicate,interpretation_kind,target_type,expected_fact_type,
      value_kind,requires_persona_identity,requires_principal_placement,bulk_eligible,status
    ) VALUES
      ('verify-name-no-bulk',1,'verify.person.name.no_bulk','property','assertion','navn',
       'text',true,false,false,'active'),
      ('verify-name-principal',1,'verify.person.name.principal','property','assertion','navn',
       'text',true,true,true,'active');
    INSERT INTO private.interpretation(
      id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
      predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id
    ) VALUES
      (v_interpretation_1,'c0000000-0000-0000-0000-000000000041',1,-987650041,v_persona,
       'property','person.name','"Anna Verify"','1.0','source_statement',1,'proposed','verify',v_run),
      (v_interpretation_2,'c0000000-0000-0000-0000-000000000042',1,-987650041,v_persona,
       'property','person.name','"Anna Verify"','1.0','source_statement',1,'proposed','verify',v_run),
      (v_interpretation_3,'c0000000-0000-0000-0000-000000000043',1,-987650041,v_persona,
       'property','person.name','"Anna Verify"','1.0','source_statement',1,'proposed','verify',v_run),
      (v_interpretation_no_bulk_1,'c0000000-0000-0000-0000-000000000044',1,-987650041,v_persona,
       'property','verify.person.name.no_bulk','"Anna Verify"','1.0','source_statement',1,'proposed','verify',v_run),
      (v_interpretation_no_bulk_2,'c0000000-0000-0000-0000-000000000045',1,-987650041,v_persona,
       'property','verify.person.name.no_bulk','"Anna Verify"','1.0','source_statement',1,'proposed','verify',v_run),
      (v_interpretation_principal,'c0000000-0000-0000-0000-000000000046',1,-987650041,v_persona,
       'property','verify.person.name.principal','"Anna Verify"','1.0','source_statement',1,'proposed','verify',v_run),
      (v_interpretation_stale,'c0000000-0000-0000-0000-000000000047',1,-987650041,v_persona,
       'property','person.name','"Anna Verify"','1.0','source_statement',1,'proposed','verify',v_run);
    INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
      VALUES (v_interpretation_1,v_observation,'supporting',1),
             (v_interpretation_2,v_observation,'supporting',1),
             (v_interpretation_3,v_observation,'supporting',1),
             (v_interpretation_no_bulk_1,v_observation,'supporting',1),
             (v_interpretation_no_bulk_2,v_observation,'supporting',1),
             (v_interpretation_principal,v_observation,'supporting',1),
             (v_interpretation_stale,v_observation,'supporting',1);
    SET CONSTRAINTS private.interpretation_has_observation IMMEDIATE;
    SET CONSTRAINTS private.interpretation_has_observation DEFERRED;

    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    PERFORM private.decide_source_persona_identity(v_persona,-987650041,0,'accepted','{"basis":"web_detail","note":"promotion verify"}','human');
    SET LOCAL ROLE authenticated;
    SELECT red_decide_interpretation(v_interpretation_1,1,'accepted','{"basis":"promotion verify"}')
      INTO v_accepted_1;
    SELECT red_decide_interpretation(v_interpretation_2,1,'accepted','{"basis":"promotion verify"}')
      INTO v_accepted_2;
    SELECT red_decide_interpretation(v_interpretation_3,1,'accepted','{"basis":"promotion verify"}')
      INTO v_accepted_3;
    SELECT red_decide_interpretation(v_interpretation_no_bulk_1,1,'accepted','{"basis":"promotion verify"}')
      INTO v_accepted_no_bulk_1;
    SELECT red_decide_interpretation(v_interpretation_no_bulk_2,1,'accepted','{"basis":"promotion verify"}')
      INTO v_accepted_no_bulk_2;
    SELECT red_decide_interpretation(v_interpretation_principal,1,'accepted','{"basis":"promotion verify"}')
      INTO v_accepted_principal;
    v_preview:=red_preview_interpretation_promotions(jsonb_build_array(
      jsonb_build_object('interpretation_id',v_accepted_1,'target_type','assertion','target_id',-987650041)
    ));
    IF v_preview->'items'->0->>'eligible'<>'true'
       OR v_preview->'items'->0->>'rule_key'<>'person-name-v1'
       OR v_preview->'items'->0->>'rule_version'<>'1'
       OR v_preview->>'preview_hash' !~ '^[0-9a-f]{64}$' THEN
      RAISE EXCEPTION 'FEJL: samme person/fact-type/tekst blev ikke previewet som eligible: %',v_preview;
    END IF;
    v_preview:=red_preview_interpretation_promotions(jsonb_build_array(
      jsonb_build_object('interpretation_id',v_interpretation_stale,'target_type','assertion','target_id',-987650041)
    ));
    IF v_preview->'items'->0->>'reason_code'<>'EVIDENCE_INTERPRETATION_NOT_ACCEPTED' THEN
      RAISE EXCEPTION 'FEJL: proposed fortolkning blev ikke afvist: %',v_preview;
    END IF;
    v_preview:=red_preview_interpretation_promotions(jsonb_build_array(
      jsonb_build_object('interpretation_id',v_accepted_no_bulk_1,'target_type','assertion','target_id',-987650041),
      jsonb_build_object('interpretation_id',v_accepted_no_bulk_2,'target_type','assertion','target_id',-987650041)
    ));
    IF v_preview->'items'->0->>'reason_code'<>'EVIDENCE_PROMOTION_BULK_NOT_ELIGIBLE' THEN
      RAISE EXCEPTION 'FEJL: non-bulk regel blev accepteret i bulkbatch: %',v_preview;
    END IF;
    v_preview:=red_preview_interpretation_promotions(jsonb_build_array(
      jsonb_build_object('interpretation_id',v_accepted_principal,'target_type','assertion','target_id',-987650041)
    ));
    IF v_preview->'items'->0->>'reason_code'<>'EVIDENCE_PROMOTION_PRINCIPAL_PLACEMENT_REQUIRED' THEN
      RAISE EXCEPTION 'FEJL: accepteret ægtefælleomtale blev fejlagtigt accepteret som principal-placement: %',v_preview;
    END IF;
    RESET ROLE;
    INSERT INTO private.source_persona_placement(
      id,source_persona_id,record_placement_id,placement_role,basis_observation_id,initial_status
    ) VALUES (
      v_principal_placement,v_persona,v_record_placement,'principal_member',v_observation,'accepted'
    );
    INSERT INTO private.source_persona_placement_decision(
      placement_id,version,decision_status,evidence,decision_origin,decided_by_name
    ) VALUES (v_principal_placement,1,'accepted','{"basis":"verify fixture"}',
              'migration','legacy placement backfill');
    SET LOCAL ROLE authenticated;
    v_preview:=red_preview_interpretation_promotions(jsonb_build_array(
      jsonb_build_object('interpretation_id',v_accepted_principal,'target_type','assertion','target_id',-987650041)
    ));
    IF v_preview->'items'->0->>'eligible'<>'true' THEN
      RAISE EXCEPTION 'FEJL: accepteret principal_member opfyldte ikke principal-placement-kravet: %',v_preview;
    END IF;
    v_preview:=red_preview_interpretation_promotions(jsonb_build_array(
      jsonb_build_object('interpretation_id',v_accepted_1,'target_type','assertion','target_id',-987650044)
    ));
    IF v_preview->'items'->0->>'reason_code'<>'EVIDENCE_PROMOTION_IDENTITY_MISMATCH' THEN
      RAISE EXCEPTION 'FEJL: forkert person gav ikke identity mismatch: %',v_preview;
    END IF;
    v_preview:=red_preview_interpretation_promotions(jsonb_build_array(
      jsonb_build_object('interpretation_id',v_accepted_1,'target_type','assertion','target_id',-987650042)
    ));
    IF v_preview->'items'->0->>'reason_code'<>'EVIDENCE_PROMOTION_FACT_TYPE_MISMATCH' THEN
      RAISE EXCEPTION 'FEJL: titel-fact gav ikke fact-type mismatch: %',v_preview;
    END IF;
    v_preview:=red_preview_interpretation_promotions(jsonb_build_array(
      jsonb_build_object('interpretation_id',v_accepted_1,'target_type','assertion','target_id',-987650043)
    ));
    IF v_preview->'items'->0->>'reason_code'<>'EVIDENCE_PROMOTION_VALUE_MISMATCH' THEN
      RAISE EXCEPTION 'FEJL: afvigende tekst gav ikke value mismatch: %',v_preview;
    END IF;

    v_preview:=red_preview_interpretation_promotions(jsonb_build_array(
      jsonb_build_object('interpretation_id',v_accepted_1,'target_type','assertion','target_id',-987650041)
    ));
    RESET ROLE;
    SELECT count(*) INTO v_before_promotions FROM private.interpretation_promotion;
    SELECT count(*) INTO v_before_batches FROM private.interpretation_promotion_batch;
    SET LOCAL ROLE authenticated;
    v_error:=NULL;
    BEGIN
      PERFORM red_promote_interpretations_batch(
        jsonb_build_array(jsonb_build_object(
          'interpretation_id',v_accepted_1,'target_type','assertion','target_id',-987650041
        )),repeat('0',64)
      );
    EXCEPTION WHEN others THEN v_error:=SQLERRM;
    END;
    RESET ROLE;
    IF v_error NOT LIKE 'EVIDENCE_PROMOTION_PREVIEW_STALE%'
       OR (SELECT count(*) FROM private.interpretation_promotion)<>v_before_promotions
       OR (SELECT count(*) FROM private.interpretation_promotion_batch)<>v_before_batches THEN
      RAISE EXCEPTION 'FEJL: forfalsket preview-hash kunne ændre promotion-audit: fejl=%',v_error;
    END IF;
    SET LOCAL ROLE authenticated;
    v_error:=NULL;
    BEGIN
      PERFORM red_promote_interpretations_batch(
        jsonb_build_array(jsonb_build_object(
          'interpretation_id',v_accepted_1,'target_type','assertion','target_id',-987650043
        )),v_preview->>'preview_hash'
      );
    EXCEPTION WHEN others THEN v_error:=SQLERRM;
    END;
    RESET ROLE;
    IF v_error NOT LIKE 'EVIDENCE_PROMOTION_PREVIEW_STALE%'
       OR (SELECT count(*) FROM private.interpretation_promotion)<>v_before_promotions
       OR (SELECT count(*) FROM private.interpretation_promotion_batch)<>v_before_batches THEN
      RAISE EXCEPTION 'FEJL: preview-hash var ikke bundet til den konkrete request: fejl=%',v_error;
    END IF;
    SELECT count(*) INTO v_before_persons FROM person;
    SELECT count(*) INTO v_before_facts FROM fact;
    SELECT count(*) INTO v_before_assertions FROM assertion;
    SET LOCAL ROLE authenticated;
    PERFORM red_promote_interpretations_batch(
      jsonb_build_array(jsonb_build_object(
        'interpretation_id',v_accepted_1,'target_type','assertion','target_id',-987650041
      )),v_preview->>'preview_hash'
    );
    RESET ROLE;
    IF (SELECT count(*) FROM private.interpretation_promotion
         WHERE interpretation_id=v_accepted_1 AND target_id=-987650041)<>1
       OR (SELECT count(*) FROM private.interpretation_promotion_batch
           WHERE requested_count=1 AND promoted_by=v_actor)<>1 THEN
      RAISE EXCEPTION 'FEJL: gyldig enkeltpromotion oprettede ikke præcis ét audit-link og batch';
    END IF;
    IF EXISTS (
      SELECT 1 FROM private.interpretation_promotion_batch
       WHERE requested_count=1 AND promoted_by=v_actor
         AND rule_profile_hash !~ '^[0-9a-f]{64}$'
    ) THEN
      RAISE EXCEPTION 'FEJL: promotionens regelprofil er ikke SHA-256-kontraktbundet';
    END IF;
    IF (SELECT count(*) FROM person)<>v_before_persons
       OR (SELECT count(*) FROM fact)<>v_before_facts
       OR (SELECT count(*) FROM assertion)<>v_before_assertions THEN
      RAISE EXCEPTION 'FEJL: promotion ændrede kanonisk genealogi';
    END IF;

    -- To forskellige accepterede fortolkninger i én gyldig batch giver præcis
    -- to audit-links og én ny batch; de opretter ikke kanoniske rækker.
    SELECT count(*) INTO v_before_promotions FROM private.interpretation_promotion;
    SELECT count(*) INTO v_before_batches FROM private.interpretation_promotion_batch;
    SELECT count(*) INTO v_before_persons FROM person;
    SELECT count(*) INTO v_before_facts FROM fact;
    SELECT count(*) INTO v_before_assertions FROM assertion;
    SET LOCAL ROLE authenticated;
    v_preview:=red_preview_interpretation_promotions(jsonb_build_array(
      jsonb_build_object('interpretation_id',v_accepted_2,'target_type','assertion','target_id',-987650041),
      jsonb_build_object('interpretation_id',v_accepted_3,'target_type','assertion','target_id',-987650041)
    ));
    PERFORM red_promote_interpretations_batch(jsonb_build_array(
      jsonb_build_object('interpretation_id',v_accepted_2,'target_type','assertion','target_id',-987650041),
      jsonb_build_object('interpretation_id',v_accepted_3,'target_type','assertion','target_id',-987650041)
    ),v_preview->>'preview_hash');
    RESET ROLE;
    IF (SELECT count(*) FROM private.interpretation_promotion)<>v_before_promotions+2
       OR (SELECT count(*) FROM private.interpretation_promotion_batch)<>v_before_batches+1
       OR (SELECT count(*) FROM person)<>v_before_persons
       OR (SELECT count(*) FROM fact)<>v_before_facts
       OR (SELECT count(*) FROM assertion)<>v_before_assertions THEN
      RAISE EXCEPTION 'FEJL: gyldig bulkbatch skrev ikke præcis to links/én batch uden kanonisk mutation';
    END IF;

    SELECT count(*) INTO v_before_promotions FROM private.interpretation_promotion;
    SELECT count(*) INTO v_before_batches FROM private.interpretation_promotion_batch;
    SET LOCAL ROLE authenticated;
    v_preview:=red_preview_interpretation_promotions(jsonb_build_array(
      jsonb_build_object('interpretation_id',v_accepted_principal,'target_type','assertion','target_id',-987650041),
      jsonb_build_object('interpretation_id',v_accepted_1,'target_type','assertion','target_id',-987650044)
    ));
    v_error:=NULL;
    BEGIN
      PERFORM red_promote_interpretations_batch(jsonb_build_array(
        jsonb_build_object('interpretation_id',v_accepted_principal,'target_type','assertion','target_id',-987650041),
        jsonb_build_object('interpretation_id',v_accepted_1,'target_type','assertion','target_id',-987650044)
      ),v_preview->>'preview_hash');
    EXCEPTION WHEN others THEN v_error:=SQLERRM;
    END;
    RESET ROLE;
    IF v_error NOT LIKE 'EVIDENCE_PROMOTION_IDENTITY_MISMATCH%'
       OR (SELECT count(*) FROM private.interpretation_promotion)<>v_before_promotions
       OR (SELECT count(*) FROM private.interpretation_promotion_batch)<>v_before_batches THEN
      RAISE EXCEPTION 'FEJL: ugyldig batch var ikke atomisk: fejl=%',v_error;
    END IF;
    SET LOCAL ROLE authenticated;
    PERFORM red_decide_source_persona_placement(
      v_principal_placement,1,'superseded','{"basis":"placement no longer current"}'
    );
    v_preview:=red_preview_interpretation_promotions(jsonb_build_array(
      jsonb_build_object('interpretation_id',v_accepted_principal,'target_type','assertion','target_id',-987650041)
    ));
    IF v_preview->'items'->0->>'reason_code'<>'EVIDENCE_PROMOTION_PRINCIPAL_PLACEMENT_REQUIRED' THEN
      RAISE EXCEPTION 'FEJL: initial_status accepted blev fejlagtigt behandlet som current efter supersede: %',v_preview;
    END IF;
    RESET ROLE;
    SELECT private.add_interpretation_promotion_rule_version(
      'person-name-v1','person.name','property','assertion','navn','text',
      true,false,true,'active'
    ) INTO v_rule_version;
    IF v_rule_version<>2 THEN RAISE EXCEPTION 'FEJL: promotionregel-version blev ikke 2'; END IF;
    SET LOCAL ROLE authenticated;
    v_preview:=red_preview_interpretation_promotions(jsonb_build_array(
      jsonb_build_object('interpretation_id',v_accepted_1,'target_type','assertion','target_id',-987650041)
    ));
    IF v_preview->'items'->0->>'rule_version'<>'2' THEN
      RAISE EXCEPTION 'FEJL: preview brugte ikke current regelversion 2: %',v_preview; END IF;
    RESET ROLE;
    SELECT private.add_interpretation_promotion_rule_version(
      'person-name-v1','person.name','property','assertion','navn','text',
      true,false,true,'retired'
    ) INTO v_rule_version;
    IF v_rule_version<>3 THEN RAISE EXCEPTION 'FEJL: promotionregel-version blev ikke 3'; END IF;
    SET LOCAL ROLE authenticated;
    v_preview:=red_preview_interpretation_promotions(jsonb_build_array(
      jsonb_build_object('interpretation_id',v_accepted_1,'target_type','assertion','target_id',-987650041)
    ));
    IF v_preview->'items'->0->>'reason_code'<>'EVIDENCE_PROMOTION_RULE_NOT_ACTIVE' THEN
      RAISE EXCEPTION 'FEJL: retired current-regel lod version 1 genopstå: %',v_preview; END IF;
    RESET ROLE;
    v_error:=NULL;
    BEGIN
      PERFORM private.add_interpretation_promotion_rule_version(
        'person-name-v1','person.renamed','property','assertion','navn','text',
        true,false,true,'active');
    EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
    IF v_error NOT LIKE 'EVIDENCE_PROMOTION_RULE_PREDICATE_MISMATCH%' THEN
      RAISE EXCEPTION 'FEJL: predicate-skift i samme regellinje blev ikke afvist: %',v_error; END IF;
    v_error:=NULL;
    BEGIN
      INSERT INTO private.interpretation_promotion_rule_line(rule_key,predicate)
        VALUES ('another-person-name','person.name');
    EXCEPTION WHEN unique_violation THEN v_error:=SQLERRM; END;
    IF v_error IS NULL THEN RAISE EXCEPTION 'FEJL: samme predicate fik en anden rule_key'; END IF;
    RAISE EXCEPTION 'ROLLBACK_PROMOTION_RPC_VERIFY';
  EXCEPTION WHEN others THEN
    IF SQLERRM='ROLLBACK_PROMOTION_RPC_VERIFY' THEN
      RAISE NOTICE 'OK: promotion-preview validerer identitet, fact-type og værdi; batch er atomisk';
    ELSE
      RAISE;
    END IF;
  END;
  RAISE NOTICE 'OK: promotionregler er eksplicitte, assertion-bundne og auditerbare';
END $promotion_rule_verify$;

DO $identity_candidate_verify$
DECLARE v_required text[] := ARRAY['source_persona_identity_candidate_run','source_persona_identity_candidate'];
BEGIN
  IF EXISTS (SELECT 1 FROM unnest(v_required) t WHERE to_regclass(format('private.%I',t)) IS NULL) THEN
    RAISE EXCEPTION 'FEJL: #151 kandidatlaget mangler';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='private' AND c.relname=ANY(v_required)
       AND (NOT c.relrowsecurity
         OR has_table_privilege('anon',c.oid,'SELECT') OR has_table_privilege('authenticated',c.oid,'SELECT')
         OR has_table_privilege('anon',c.oid,'INSERT') OR has_table_privilege('authenticated',c.oid,'INSERT'))
  ) THEN
    RAISE EXCEPTION 'FEJL: #151 kandidatlaget har API-rettigheder eller mangler RLS';
  END IF;
  RAISE NOTICE 'OK: #151 kandidatlaget findes med RLS og uden API-rettigheder';
END $identity_candidate_verify$;

DO $relation_party_verify$
BEGIN
  IF to_regclass('private.interpretation_party') IS NULL OR to_regclass('private.interpretation_party_current') IS NULL THEN
    RAISE EXCEPTION 'EVIDENCE_RELATION_PARTY_MISSING';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private.interpretation_party'::regclass) THEN
    RAISE EXCEPTION 'EVIDENCE_RELATION_PARTY_RLS_OFF';
  END IF;
  IF has_table_privilege('authenticated','private.interpretation_party','SELECT')
     OR has_table_privilege('anon','private.interpretation_party','SELECT') THEN
    RAISE EXCEPTION 'EVIDENCE_RELATION_PARTY_GRANT';
  END IF;
END $relation_party_verify$;

-- Trin 5b (spec §7): kontrolkørslens tre tabeller findes, har RLS og er lukket for klientroller.
DO $identity_control_verify$
DECLARE v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['identity_control_run','identity_control_sample','identity_control_event'] LOOP
    IF to_regclass('private.'||v_table) IS NULL THEN RAISE EXCEPTION 'EVIDENCE_IDENTITY_CONTROL_MISSING: %',v_table; END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=('private.'||v_table)::regclass) THEN
      RAISE EXCEPTION 'EVIDENCE_IDENTITY_CONTROL_RLS_OFF: %',v_table;
    END IF;
    IF has_table_privilege('authenticated','private.'||v_table,'SELECT')
       OR has_table_privilege('anon','private.'||v_table,'SELECT') THEN
      RAISE EXCEPTION 'EVIDENCE_IDENTITY_CONTROL_GRANT: %',v_table;
    END IF;
  END LOOP;
END $identity_control_verify$;

-- Preview må aldrig kunne promovere mod en revision, der skifter efter preview.
-- Denne er en reel to-sessions-test: A afgør den accepterede fortolkning igen,
-- B's batch skal blokere på current-revisionen og derefter afvises som stale.
DO $promotion_concurrency$
DECLARE
  v_conn text := format(
    'dbname=%s port=%s host=%s',current_database(),current_setting('port'),
    split_part(current_setting('unix_socket_directories'),',',1)
  );
  v_actor uuid := '11000000-0000-0000-0000-000000000051';
  v_run uuid := '22000000-0000-0000-0000-000000000051';
  v_rendition uuid := '33000000-0000-0000-0000-000000000051';
  v_occurrence uuid := '55000000-0000-0000-0000-000000000051';
  v_observation uuid := '66000000-0000-0000-0000-000000000051';
  v_mention uuid := '77000000-0000-0000-0000-000000000051';
  v_persona uuid := '88000000-0000-0000-0000-000000000051';
  v_interpretation_1 uuid := 'c1000000-0000-0000-0000-000000000051';
  v_interpretation_2 uuid := 'c1000000-0000-0000-0000-000000000052';
  v_identity_interpretation_1 uuid := 'c1000000-0000-0000-0000-000000000053';
  v_identity_interpretation_2 uuid := 'c1000000-0000-0000-0000-000000000054';
  v_a_pid integer;
  v_b_pid integer;
  v_busy integer;
  v_preview_hash text;
  v_error text;
  v_version integer;
  v_deadline timestamptz;
  v_setup_connected boolean := false;
  v_a_connected boolean := false;
  v_b_connected boolean := false;
  v_cleanup text := $cleanup$
    SET session_replication_role=replica;
    DELETE FROM private.interpretation_promotion
      WHERE interpretation_id IN ('c1000000-0000-0000-0000-000000000051',
                                  'c1000000-0000-0000-0000-000000000052',
                                  'c1000000-0000-0000-0000-000000000053',
                                  'c1000000-0000-0000-0000-000000000054');
    DELETE FROM private.interpretation_promotion_batch
      WHERE promoted_by='11000000-0000-0000-0000-000000000051';
    DELETE FROM private.interpretation_promotion_rule
      WHERE rule_key='verify-concurrent-name';
    DELETE FROM private.interpretation_promotion_rule_line
      WHERE rule_key='verify-concurrent-name';
    -- (#198) Tre led, ikke ét. Blokken kopierer senere en fortolkning til et id fra
    -- gen_random_uuid() og haenger interpretation_observation-raekker paa DET id, saa en
    -- liste over faste fixture-id'er kan ikke daekke barnet. Foraelderen blev ryddet af
    -- OR source_id=-987650051 nedenfor; barnet overlevede og stod tilbage med BEGGE
    -- fremmednoegler haengende. Det braekkede constraint-genskabelsen ved
    -- pg_restore --clean (maalt 2026-09-17: 2 fremmednoegler foer, 0 efter).
    --   led 2: alt der hoerer til fixturens source, ogsaa de tilfaeldige id'er
    --   led 3: rydder ogsaa op efter TIDLIGERE koersler, hvor foraelderen allerede er
    --          slettet — det er den tilstand enhver base staar i, som db-verify har
    --          koert mod foer denne rettelse
    DELETE FROM private.interpretation_observation
      WHERE interpretation_id IN ('c1000000-0000-0000-0000-000000000051',
                                  'c1000000-0000-0000-0000-000000000052',
                                  'c1000000-0000-0000-0000-000000000053',
                                  'c1000000-0000-0000-0000-000000000054')
         OR interpretation_id IN (SELECT id FROM private.interpretation
                                   WHERE source_id=-987650051)
         OR observation_id='66000000-0000-0000-0000-000000000051';
    DELETE FROM private.interpretation
      WHERE id IN ('c1000000-0000-0000-0000-000000000051',
                   'c1000000-0000-0000-0000-000000000052',
                   'c1000000-0000-0000-0000-000000000053',
                   'c1000000-0000-0000-0000-000000000054')
         OR source_id=-987650051;
    DELETE FROM private.source_persona_identity_event
      WHERE source_persona_id='88000000-0000-0000-0000-000000000051';
    DELETE FROM private.source_persona_identity
      WHERE source_persona_id='88000000-0000-0000-0000-000000000051';
    DELETE FROM private.source_persona_mention
      WHERE persona_id='88000000-0000-0000-0000-000000000051';
    DELETE FROM private.source_persona
      WHERE id='88000000-0000-0000-0000-000000000051';
    DELETE FROM private.source_mention WHERE id='77000000-0000-0000-0000-000000000051';
    DELETE FROM private.source_observation WHERE id='66000000-0000-0000-0000-000000000051';
    DELETE FROM private.source_record_occurrence WHERE id='55000000-0000-0000-0000-000000000051';
    DELETE FROM private.source_rendition WHERE id='33000000-0000-0000-0000-000000000051';
    DELETE FROM private.extraction_run WHERE id='22000000-0000-0000-0000-000000000051';
    DELETE FROM assertion WHERE id=-987650051;
    DELETE FROM fact WHERE id=-987650051;
    DELETE FROM source WHERE id=-987650051;
    DELETE FROM profiles WHERE id='11000000-0000-0000-0000-000000000051';
    DELETE FROM auth.users WHERE id='11000000-0000-0000-0000-000000000051';
    DELETE FROM person WHERE id IN (-987650051,-987650052);
    SET session_replication_role=origin;
  $cleanup$;
BEGIN
  IF to_regprocedure('dblink_connect(text,text)') IS NULL THEN
    RAISE EXCEPTION 'DB_VERIFY_DBLINK_REQUIRED: promotion-samtidighed';
  END IF;
  PERFORM dblink_connect('promotion_setup',v_conn||' application_name=daa_verify_promotion_setup');
  v_setup_connected:=true;
  PERFORM dblink_exec('promotion_setup',v_cleanup);
  PERFORM dblink_exec('promotion_setup','BEGIN');
  PERFORM dblink_exec('promotion_setup',format(
    'INSERT INTO auth.users(id,email) VALUES (''%s'',''promotion-lock@test.invalid'')',v_actor));
  PERFORM dblink_exec('promotion_setup',format(
    'INSERT INTO profiles(id,rolle,email,navn) VALUES (''%s'',''redaktion'',%L,''Promotion Editor'')',
    v_actor,'promotion-lock@test.invalid'));
  PERFORM dblink_exec('promotion_setup',
    'INSERT INTO person(id,levende,privat,status) VALUES '
    || '(-987650051,false,false,''promotion lock original''),'
    || '(-987650052,false,false,''promotion lock identity successor'');'
    || 'INSERT INTO source(id,titel,import_key) VALUES (-987650051,''Promotion lock'',''verify:promotion:lock'');');
  PERFORM dblink_exec('promotion_setup',format(
    'INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) '
    || 'VALUES (''%s'',-987650051,''promotion-lock-run'',''1.0'',''verify'',''verify'',%L,''{}'')',
    v_run,repeat('5',64)));
  PERFORM dblink_exec('promotion_setup',format(
    'INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata) '
    || 'VALUES (''%s'',-987650051,''promotion-lock-rendition'',''text_layer'',%L,''{}'')',
    v_rendition,repeat('6',64)));
  PERFORM dblink_exec('promotion_setup',format(
    'INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id) '
    || 'VALUES (''%s'',''%s'',''promotion-lock-occurrence'',1,1,0,13,''Anna Lock'',''physical-promotion-lock'',''structural-promotion-lock'',''%s'')',
    v_occurrence,v_rendition,v_run));
  PERFORM dblink_exec('promotion_setup',format(
    'INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id) '
    || 'VALUES (''%s'',''%s'',''name_clause'',1,1,0,13,''Anna Lock'',''clear'',''verify'',''%s'')',
    v_observation,v_occurrence,v_run));
  PERFORM dblink_exec('promotion_setup',format(
    'INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) '
    || 'VALUES (''%s'',-987650051,''promotion-lock-persona'',''%s'')',v_persona,v_run));
  PERFORM dblink_exec('promotion_setup',format(
    'INSERT INTO private.source_mention(id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id) '
    || 'VALUES (''%s'',''%s'',''person'',0,4,''Anna'',''%s'');'
    || 'INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) '
    || 'VALUES (''%s'',''%s'',''principal'',1)',
    v_mention,v_observation,v_run,v_persona,v_mention));
  PERFORM dblink_exec('promotion_setup',
    'INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-987650051,''person'',-987650051,''navn'');'
    || 'INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,calendar,uforanderlig) '
    || 'VALUES (-987650051,''fact'',-987650051,''Anna Lock'',''gregoriansk'',true);');
  PERFORM dblink_exec('promotion_setup',
    'INSERT INTO private.interpretation_promotion_rule_line(rule_key,predicate) '
    || 'VALUES (''verify-concurrent-name'',''verify.concurrent.name'');'
    || 'INSERT INTO private.interpretation_promotion_rule(rule_key,rule_version,predicate,interpretation_kind,target_type,expected_fact_type,value_kind,requires_persona_identity,requires_principal_placement,bulk_eligible,status) '
    || 'VALUES (''verify-concurrent-name'',1,''verify.concurrent.name'',''property'',''assertion'',''navn'',''text'',true,false,true,''active'');');
  PERFORM dblink_exec('promotion_setup',format(
    'INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at) '
    || 'VALUES (''%s'',-987650051,''accepted'',1,''{"basis":"verify"}'',''%s'',''Promotion Editor'',now());'
    || 'INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at) '
    || 'VALUES (''%s'',-987650051,''accepted'',1,''{"basis":"verify"}'',''%s'',''Promotion Editor'',now())',
    v_persona,v_actor,v_persona,v_actor));
  PERFORM dblink_exec('promotion_setup',format(
    'INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id) '
    || 'VALUES (''%s'',''c0000000-0000-0000-0000-000000000051'',1,-987650051,''%s'',''property'',''person.name'',''"Anna Lock"'',''1.0'',''source_statement'',1,''proposed'',''verify'',''%s'');'
    || 'INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal) VALUES (''%s'',''%s'',''supporting'',1);'
    || 'INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id,supersedes_id,decision_evidence,decided_by,decided_by_name,decided_at) '
    || 'VALUES (''%s'',''c0000000-0000-0000-0000-000000000051'',2,-987650051,''%s'',''property'',''person.name'',''"Anna Lock"'',''1.0'',''source_statement'',1,''accepted'',''verify'',''%s'',''%s'',''{"basis":"verify"}'',''%s'',''Promotion Editor'',clock_timestamp());'
    || 'INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal) VALUES (''%s'',''%s'',''supporting'',1);'
    || 'INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id) '
    || 'VALUES (''%s'',''c0000000-0000-0000-0000-000000000052'',1,-987650051,''%s'',''property'',''verify.concurrent.name'',''"Anna Lock"'',''1.0'',''source_statement'',1,''proposed'',''verify'',''%s'');'
    || 'INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal) VALUES (''%s'',''%s'',''supporting'',1);'
    || 'INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id,supersedes_id,decision_evidence,decided_by,decided_by_name,decided_at) '
    || 'VALUES (''%s'',''c0000000-0000-0000-0000-000000000052'',2,-987650051,''%s'',''property'',''verify.concurrent.name'',''"Anna Lock"'',''1.0'',''source_statement'',1,''accepted'',''verify'',''%s'',''%s'',''{"basis":"verify"}'',''%s'',''Promotion Editor'',clock_timestamp());'
    || 'INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal) VALUES (''%s'',''%s'',''supporting'',1)',
    v_interpretation_1,v_persona,v_run,v_interpretation_1,v_observation,
    v_interpretation_2,v_persona,v_run,v_interpretation_1,v_actor,v_interpretation_2,v_observation,
    v_identity_interpretation_1,v_persona,v_run,v_identity_interpretation_1,v_observation,
    v_identity_interpretation_2,v_persona,v_run,v_identity_interpretation_1,v_actor,
    v_identity_interpretation_2,v_observation));
  PERFORM dblink_exec('promotion_setup','COMMIT');

  PERFORM dblink_connect('promotion_a',v_conn||' application_name=daa_verify_promotion_a');
  v_a_connected:=true;
  PERFORM dblink_connect('promotion_b',v_conn||' application_name=daa_verify_promotion_b');
  v_b_connected:=true;
  SELECT pid INTO v_a_pid FROM dblink('promotion_a','SELECT pg_backend_pid()') AS t(pid integer);
  SELECT pid INTO v_b_pid FROM dblink('promotion_b','SELECT pg_backend_pid()') AS t(pid integer);
  PERFORM dblink_exec('promotion_a','BEGIN');
  PERFORM dblink_exec('promotion_a','SET LOCAL ROLE authenticated');
  PERFORM dblink_exec('promotion_a',format('SET LOCAL "request.jwt.claim.sub"=%L',v_actor::text));
  SELECT preview->>'preview_hash' INTO v_preview_hash
    FROM dblink('promotion_a',format(
      'SELECT red_preview_interpretation_promotions(''[{"interpretation_id":"%s","target_type":"assertion","target_id":-987650051}]''::jsonb) AS preview',
      v_interpretation_2)) AS t(preview jsonb);
  IF v_preview_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'FEJL: promotion-samtidighed fik ikke SHA-256-preview';
  END IF;
  -- Simulér en separat, append-only current-version mellem preview og batch.
  -- Det er med vilje ikke red_decide_interpretation(): #155 tillader kun den
  -- RPC på proposals, mens stale-preview-gaten stadig skal tåle en ændret
  -- ledger-version fra en anden autoriseret write-vej.
  PERFORM dblink_exec('promotion_a','RESET ROLE');
  PERFORM dblink_exec('promotion_a',format(
    'WITH created AS (INSERT INTO private.interpretation('
    || 'id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,predicate,value,'
    || 'schema_version,derivation_kind,confidence,status,method,model_version,prompt_version,'
    || 'extraction_run_id,supersedes_id,decision_evidence,decided_by,decided_by_name,decided_at) '
    || 'SELECT gen_random_uuid(),interpretation_key,version+1,source_id,source_persona_id,interpretation_kind,predicate,value,'
    || 'schema_version,derivation_kind,confidence,''rejected'',method,model_version,prompt_version,'
    || 'extraction_run_id,id,''{"basis":"concurrent ledger change"}'',%L,''Promotion Editor'',clock_timestamp() '
    || 'FROM private.interpretation WHERE id=''%s'' RETURNING id) '
    || 'INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal) '
    || 'SELECT created.id,io.observation_id,io.evidence_role,io.ordinal '
    || 'FROM created JOIN private.interpretation_observation io ON io.interpretation_id=''%s''',
    v_actor::text,v_interpretation_2,v_interpretation_2));

  PERFORM dblink_exec('promotion_b','BEGIN');
  PERFORM dblink_exec('promotion_b','SET LOCAL ROLE authenticated');
  PERFORM dblink_exec('promotion_b',format('SET LOCAL "request.jwt.claim.sub"=%L',v_actor::text));
  PERFORM dblink_send_query('promotion_b',format(
    'SELECT red_promote_interpretations_batch(''[{"interpretation_id":"%s","target_type":"assertion","target_id":-987650051}]''::jsonb,%L)',
    v_interpretation_2,v_preview_hash));
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP
    EXIT WHEN v_a_pid=ANY(pg_blocking_pids(v_b_pid));
    SELECT dblink_is_busy('promotion_b') INTO v_busy;
    IF v_busy=0 OR clock_timestamp()>v_deadline THEN
      RAISE EXCEPTION 'FEJL: promotion-batch blev ikke serialiseret på current fortolkning';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  PERFORM dblink_exec('promotion_a','COMMIT');
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP
    SELECT dblink_is_busy('promotion_b') INTO v_busy;
    EXIT WHEN v_busy=0;
    IF clock_timestamp()>v_deadline THEN
      RAISE EXCEPTION 'FEJL: promotion-batch afsluttede ikke efter concurrent COMMIT';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  v_error:=NULL;
  BEGIN
    PERFORM * FROM dblink_get_result('promotion_b') AS t(batch_id uuid);
  EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
  BEGIN
    PERFORM * FROM dblink_get_result('promotion_b') AS t(batch_id uuid);
  EXCEPTION WHEN others THEN IF v_error IS NULL THEN v_error:=SQLERRM; END IF; END;
  IF v_error NOT LIKE '%EVIDENCE_PROMOTION_PREVIEW_STALE%' THEN
    RAISE EXCEPTION 'FEJL: concurrent promotion fejlede ikke stale/fail-closed: %',v_error;
  END IF;
  PERFORM dblink_exec('promotion_b','ROLLBACK');
  PERFORM dblink_disconnect('promotion_a'); v_a_connected:=false;
  PERFORM dblink_disconnect('promotion_b'); v_b_connected:=false;
  IF EXISTS (SELECT 1 FROM private.interpretation_promotion WHERE interpretation_id=v_interpretation_2)
     OR EXISTS (SELECT 1 FROM private.interpretation_promotion_batch WHERE promoted_by=v_actor) THEN
    RAISE EXCEPTION 'FEJL: concurrent stale promotion efterlod audit-skrivning';
  END IF;

  -- A ændrer identity-state gennem den rigtige redaktør-RPC. B har allerede
  -- startet batchen og låser den aktuelle fortolkning, men skal derefter vente
  -- på persona/identity-låsen og genberegne fail-closed efter A's COMMIT.
  PERFORM dblink_connect('promotion_a',v_conn||' application_name=daa_verify_promotion_identity_a');
  v_a_connected:=true;
  PERFORM dblink_connect('promotion_b',v_conn||' application_name=daa_verify_promotion_identity_b');
  v_b_connected:=true;
  SELECT pid INTO v_a_pid FROM dblink('promotion_a','SELECT pg_backend_pid()') AS t(pid integer);
  SELECT pid INTO v_b_pid FROM dblink('promotion_b','SELECT pg_backend_pid()') AS t(pid integer);
  PERFORM dblink_exec('promotion_a','BEGIN');
  PERFORM dblink_exec('promotion_a','SET LOCAL ROLE authenticated');
  PERFORM dblink_exec('promotion_a',format('SET LOCAL "request.jwt.claim.sub"=%L',v_actor::text));
  SELECT preview->>'preview_hash' INTO v_preview_hash
    FROM dblink('promotion_a',format(
      'SELECT red_preview_interpretation_promotions(''[{"interpretation_id":"%s","target_type":"assertion","target_id":-987650051}]''::jsonb) AS preview',
      v_identity_interpretation_2)) AS t(preview jsonb);
  PERFORM dblink_exec('promotion_a','RESET ROLE');   -- #151: kernen er privat; kaldes som server
  SELECT version INTO v_version FROM dblink('promotion_a',format(
    'SELECT private.decide_source_persona_identity(''%s'',-987650052,1,''accepted'',''{"basis":"web_detail","note":"concurrent identity review"}'',''human'')',
    v_persona)) AS t(version integer);
  PERFORM dblink_exec('promotion_a','SET LOCAL ROLE authenticated');
  IF v_version<>2 THEN
    RAISE EXCEPTION 'FEJL: concurrent identity-writer gav version %',v_version;
  END IF;
  PERFORM dblink_exec('promotion_b','BEGIN');
  PERFORM dblink_exec('promotion_b','SET LOCAL ROLE authenticated');
  PERFORM dblink_exec('promotion_b',format('SET LOCAL "request.jwt.claim.sub"=%L',v_actor::text));
  PERFORM dblink_send_query('promotion_b',format(
    'SELECT red_promote_interpretations_batch(''[{"interpretation_id":"%s","target_type":"assertion","target_id":-987650051}]''::jsonb,%L)',
    v_identity_interpretation_2,v_preview_hash));
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP
    EXIT WHEN v_a_pid=ANY(pg_blocking_pids(v_b_pid));
    SELECT dblink_is_busy('promotion_b') INTO v_busy;
    IF v_busy=0 OR clock_timestamp()>v_deadline THEN
      RAISE EXCEPTION 'FEJL: promotion-batch nåede ikke persona/identity-låsen';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  PERFORM dblink_exec('promotion_a','COMMIT');
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP
    SELECT dblink_is_busy('promotion_b') INTO v_busy;
    EXIT WHEN v_busy=0;
    IF clock_timestamp()>v_deadline THEN
      RAISE EXCEPTION 'FEJL: promotion-batch afsluttede ikke efter identity-COMMIT';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  v_error:=NULL;
  BEGIN
    PERFORM * FROM dblink_get_result('promotion_b') AS t(batch_id uuid);
  EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
  BEGIN
    PERFORM * FROM dblink_get_result('promotion_b') AS t(batch_id uuid);
  EXCEPTION WHEN others THEN IF v_error IS NULL THEN v_error:=SQLERRM; END IF; END;
  IF v_error NOT LIKE '%EVIDENCE_PROMOTION_PREVIEW_STALE%' THEN
    RAISE EXCEPTION 'FEJL: identity-racet promotion fejlede ikke stale/fail-closed: %',v_error;
  END IF;
  PERFORM dblink_exec('promotion_b','ROLLBACK');
  PERFORM dblink_disconnect('promotion_a'); v_a_connected:=false;
  PERFORM dblink_disconnect('promotion_b'); v_b_connected:=false;
  IF NOT EXISTS (
       SELECT 1 FROM private.source_persona_identity
        WHERE source_persona_id=v_persona AND canonical_person_id=-987650052
          AND decision_status='accepted' AND version=2
     )
     OR EXISTS (SELECT 1 FROM private.interpretation_promotion
                 WHERE interpretation_id=v_identity_interpretation_2)
     OR EXISTS (SELECT 1 FROM private.interpretation_promotion_batch WHERE promoted_by=v_actor) THEN
    RAISE EXCEPTION 'FEJL: identity-racet promotion efterlod forkert state eller audit-skrivning';
  END IF;

  -- En ny regelversion låser regellinjen. Batchen med et v1-preview skal vente,
  -- genberegne efter commit og afvise hash'en i stedet for at bruge v2 uset.
  PERFORM dblink_connect('promotion_a',v_conn||' application_name=daa_verify_promotion_rule_a');
  v_a_connected:=true;
  PERFORM dblink_connect('promotion_b',v_conn||' application_name=daa_verify_promotion_rule_b');
  v_b_connected:=true;
  SELECT pid INTO v_a_pid FROM dblink('promotion_a','SELECT pg_backend_pid()') AS t(pid integer);
  SELECT pid INTO v_b_pid FROM dblink('promotion_b','SELECT pg_backend_pid()') AS t(pid integer);
  PERFORM dblink_exec('promotion_a','BEGIN');
  PERFORM dblink_exec('promotion_a','SET LOCAL ROLE authenticated');
  PERFORM dblink_exec('promotion_a',format('SET LOCAL "request.jwt.claim.sub"=%L',v_actor::text));
  PERFORM dblink_exec('promotion_a','RESET ROLE');   -- #151: kernen er privat; kaldes som server
  SELECT version INTO v_version FROM dblink('promotion_a',format(
    'SELECT private.decide_source_persona_identity(''%s'',-987650051,2,''accepted'',''{"basis":"web_detail","note":"restore for rule race"}'',''human'')',
    v_persona)) AS t(version integer);
  PERFORM dblink_exec('promotion_a','SET LOCAL ROLE authenticated');
  IF v_version<>3 THEN RAISE EXCEPTION 'FEJL: identity restore gav version %',v_version; END IF;
  PERFORM dblink_exec('promotion_a','COMMIT');
  PERFORM dblink_exec('promotion_a','BEGIN');
  PERFORM dblink_exec('promotion_a','SET LOCAL ROLE authenticated');
  PERFORM dblink_exec('promotion_a',format('SET LOCAL "request.jwt.claim.sub"=%L',v_actor::text));
  SELECT preview->>'preview_hash' INTO v_preview_hash
    FROM dblink('promotion_a',format(
      'SELECT red_preview_interpretation_promotions(''[{"interpretation_id":"%s","target_type":"assertion","target_id":-987650051}]''::jsonb) AS preview',
      v_identity_interpretation_2)) AS t(preview jsonb);
  PERFORM dblink_exec('promotion_a','COMMIT');
  PERFORM dblink_exec('promotion_a','BEGIN');
  SELECT version INTO v_version FROM dblink('promotion_a',
    'SELECT private.add_interpretation_promotion_rule_version('
    || '''verify-concurrent-name'',''verify.concurrent.name'',''property'',''assertion'',''navn'',''text'',true,false,true,''active'')'
  ) AS t(version integer);
  IF v_version<>2 THEN RAISE EXCEPTION 'FEJL: concurrent regel-writer gav version %',v_version; END IF;
  PERFORM dblink_exec('promotion_b','BEGIN');
  PERFORM dblink_exec('promotion_b','SET LOCAL ROLE authenticated');
  PERFORM dblink_exec('promotion_b',format('SET LOCAL "request.jwt.claim.sub"=%L',v_actor::text));
  PERFORM dblink_send_query('promotion_b',format(
    'SELECT red_promote_interpretations_batch(''[{"interpretation_id":"%s","target_type":"assertion","target_id":-987650051}]''::jsonb,%L)',
    v_identity_interpretation_2,v_preview_hash));
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP
    EXIT WHEN v_a_pid=ANY(pg_blocking_pids(v_b_pid));
    SELECT dblink_is_busy('promotion_b') INTO v_busy;
    IF v_busy=0 OR clock_timestamp()>v_deadline THEN
      RAISE EXCEPTION 'FEJL: promotion-batch ventede ikke på regellinjen'; END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  PERFORM dblink_exec('promotion_a','COMMIT');
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP SELECT dblink_is_busy('promotion_b') INTO v_busy; EXIT WHEN v_busy=0;
    IF clock_timestamp()>v_deadline THEN RAISE EXCEPTION 'FEJL: rule-race batch afsluttede ikke'; END IF;
    PERFORM pg_sleep(0.02); END LOOP;
  v_error:=NULL;
  BEGIN PERFORM * FROM dblink_get_result('promotion_b') AS t(batch_id uuid);
  EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
  BEGIN PERFORM * FROM dblink_get_result('promotion_b') AS t(batch_id uuid);
  EXCEPTION WHEN others THEN IF v_error IS NULL THEN v_error:=SQLERRM; END IF; END;
  IF v_error NOT LIKE '%EVIDENCE_PROMOTION_PREVIEW_STALE%' THEN
    RAISE EXCEPTION 'FEJL: rule-racet promotion fejlede ikke stale/fail-closed: %',v_error; END IF;
  PERFORM dblink_exec('promotion_b','ROLLBACK');
  PERFORM dblink_disconnect('promotion_a'); v_a_connected:=false;
  PERFORM dblink_disconnect('promotion_b'); v_b_connected:=false;
  IF EXISTS(SELECT 1 FROM private.interpretation_promotion
             WHERE interpretation_id=v_identity_interpretation_2) THEN
    RAISE EXCEPTION 'FEJL: rule-racet efterlod promotion med skjult regelversion'; END IF;
  PERFORM dblink_exec('promotion_setup',v_cleanup);
  PERFORM dblink_disconnect('promotion_setup'); v_setup_connected:=false;
  PERFORM set_config('daa.verify_dblink_promotion','executed',false);
  RAISE NOTICE 'OK: promotion-batch låser current fortolkning og personaidentitet og afviser stale preview';
EXCEPTION WHEN others THEN
  IF v_a_connected THEN
    BEGIN PERFORM dblink_exec('promotion_a','ROLLBACK'); EXCEPTION WHEN others THEN NULL; END;
    BEGIN PERFORM dblink_disconnect('promotion_a'); EXCEPTION WHEN others THEN NULL; END;
  END IF;
  IF v_b_connected THEN
    BEGIN PERFORM dblink_exec('promotion_b','ROLLBACK'); EXCEPTION WHEN others THEN NULL; END;
    BEGIN PERFORM dblink_disconnect('promotion_b'); EXCEPTION WHEN others THEN NULL; END;
  END IF;
  IF v_setup_connected THEN
    BEGIN PERFORM dblink_exec('promotion_setup',v_cleanup); EXCEPTION WHEN others THEN NULL; END;
    BEGIN PERFORM dblink_disconnect('promotion_setup'); EXCEPTION WHEN others THEN NULL; END;
  END IF;
  RAISE;
END $promotion_concurrency$;

-- To redaktørtransaktioner fra samme identity-version: persona-låsen skal
-- serialisere dem, og den tabende afgørelse skal fejle på expected_version.
DO $identity_concurrency$
DECLARE
  v_conn text := format(
    'dbname=%s port=%s host=%s',current_database(),current_setting('port'),
    split_part(current_setting('unix_socket_directories'),',',1)
  );
  v_actor uuid := '11000000-0000-0000-0000-000000000031';
  v_persona uuid := '88000000-0000-0000-0000-000000000031';
  v_a_pid integer;
  v_b_pid integer;
  v_busy integer;
  v_version integer;
  v_deadline timestamptz;
  v_error text;
  v_setup_connected boolean := false;
  v_a_connected boolean := false;
  v_b_connected boolean := false;
  v_cleanup text := $cleanup$
    SET session_replication_role=replica;
    DELETE FROM private.source_persona_identity_event
      WHERE source_persona_id='88000000-0000-0000-0000-000000000031';
    DELETE FROM private.source_persona_identity
      WHERE source_persona_id='88000000-0000-0000-0000-000000000031';
    DELETE FROM private.source_persona_mention
      WHERE persona_id='88000000-0000-0000-0000-000000000031';
    DELETE FROM private.source_persona
      WHERE id='88000000-0000-0000-0000-000000000031';
    DELETE FROM private.source_mention
      WHERE id='77000000-0000-0000-0000-000000000031';
    DELETE FROM private.source_observation
      WHERE id='66000000-0000-0000-0000-000000000031';
    DELETE FROM private.source_record_occurrence
      WHERE id='55000000-0000-0000-0000-000000000031';
    DELETE FROM private.source_rendition
      WHERE id='33000000-0000-0000-0000-000000000031';
    DELETE FROM private.extraction_run
      WHERE id='22000000-0000-0000-0000-000000000031';
    DELETE FROM source WHERE id=-987650031;
    DELETE FROM profiles WHERE id='11000000-0000-0000-0000-000000000031';
    DELETE FROM auth.users WHERE id='11000000-0000-0000-0000-000000000031';
    DELETE FROM person WHERE id IN (-987650031,-987650032);
    SET session_replication_role=origin;
  $cleanup$;
BEGIN
  IF to_regprocedure('dblink_connect(text,text)') IS NULL THEN
    RAISE EXCEPTION 'DB_VERIFY_DBLINK_REQUIRED: identity-samtidighed';
  END IF;
  PERFORM dblink_connect('identity_setup',v_conn||' application_name=daa_verify_identity_setup');
  v_setup_connected:=true;
  PERFORM dblink_exec('identity_setup',v_cleanup);
  PERFORM dblink_exec('identity_setup',format(
    'INSERT INTO auth.users(id,email) VALUES (''%s'',''identity-lock@test.invalid'')',v_actor));
  PERFORM dblink_exec('identity_setup',
    'INSERT INTO person(id,levende,privat,status) VALUES '
    || '(-987650031,false,false,''identity A''),(-987650032,false,false,''identity B'')');
  PERFORM dblink_exec('identity_setup',format(
    'INSERT INTO profiles(id,rolle,email,navn) VALUES '
    || '(''%s'',''redaktion'',''identity-lock@test.invalid'',''Identity Editor'')',v_actor));
  PERFORM dblink_exec('identity_setup',
    'INSERT INTO source(id,titel,import_key) VALUES '
    || '(-987650031,''Identity lock'',''verify:identity:lock'')');
  PERFORM dblink_exec('identity_setup',
    'INSERT INTO private.extraction_run('
    || 'id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) '
    || 'VALUES (''22000000-0000-0000-0000-000000000031'',-987650031,''identity-lock-run'','
    || '''1.0'',''verify'',''verify'',' || quote_literal(repeat('3',64)) || ',''{}'')');
  PERFORM dblink_exec('identity_setup',
    'INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES '
    || '(''88000000-0000-0000-0000-000000000031'',-987650031,''identity-lock-persona'','
    || '''22000000-0000-0000-0000-000000000031'')');
  PERFORM dblink_exec('identity_setup',
    'INSERT INTO private.source_rendition('
    || 'id,source_id,rendition_key,rendition_kind,content_sha256,metadata) VALUES '
    || '(''33000000-0000-0000-0000-000000000031'',-987650031,''identity-lock-rendition'','
    || '''text_layer'',' || quote_literal(repeat('4',64)) || ',''{}'')');
  PERFORM dblink_exec('identity_setup',
    'INSERT INTO private.source_record_occurrence('
    || 'id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,'
    || 'physical_fingerprint,structural_fingerprint,extraction_run_id) VALUES '
    || '(''55000000-0000-0000-0000-000000000031'','
    || '''33000000-0000-0000-0000-000000000031'',''identity-lock-occurrence'',1,1,0,4,'
    || '''Anna'',''identity-physical'',''identity-structural'','
    || '''22000000-0000-0000-0000-000000000031'')');
  PERFORM dblink_exec('identity_setup',
    'INSERT INTO private.source_observation('
    || 'id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,'
    || 'quality_status,extraction_method,extraction_run_id) VALUES '
    || '(''66000000-0000-0000-0000-000000000031'','
    || '''55000000-0000-0000-0000-000000000031'',''person_name'',1,1,0,4,''Anna'','
    || '''clear'',''verify'',''22000000-0000-0000-0000-000000000031'')');
  PERFORM dblink_exec('identity_setup',
    'INSERT INTO private.source_mention('
    || 'id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id) VALUES '
    || '(''77000000-0000-0000-0000-000000000031'','
    || '''66000000-0000-0000-0000-000000000031'',''person'',0,4,''Anna'','
    || '''22000000-0000-0000-0000-000000000031'')');
  PERFORM dblink_exec('identity_setup',
    'INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES '
    || '(''88000000-0000-0000-0000-000000000031'','
    || '''77000000-0000-0000-0000-000000000031'',''principal'',1)');
  PERFORM dblink_exec('identity_setup','BEGIN');
  PERFORM dblink_exec('identity_setup',
    'INSERT INTO private.source_persona_identity_event('
    || 'source_persona_id,canonical_person_id,decision_status,version,evidence) VALUES '
    || '(''88000000-0000-0000-0000-000000000031'',NULL,''proposed'',1,''{}'')');
  PERFORM dblink_exec('identity_setup',
    'INSERT INTO private.source_persona_identity('
    || 'source_persona_id,canonical_person_id,decision_status,version,evidence) VALUES '
    || '(''88000000-0000-0000-0000-000000000031'',NULL,''proposed'',1,''{}'')');
  PERFORM dblink_exec('identity_setup','COMMIT');

  PERFORM dblink_connect('identity_a',v_conn||' application_name=daa_verify_identity_a');
  v_a_connected:=true;
  PERFORM dblink_connect('identity_b',v_conn||' application_name=daa_verify_identity_b');
  v_b_connected:=true;
  SELECT pid INTO v_a_pid FROM dblink('identity_a','SELECT pg_backend_pid()') AS t(pid integer);
  SELECT pid INTO v_b_pid FROM dblink('identity_b','SELECT pg_backend_pid()') AS t(pid integer);

  PERFORM dblink_exec('identity_a','BEGIN');
  PERFORM dblink_exec('identity_a','SET LOCAL ROLE authenticated');
  PERFORM dblink_exec('identity_a',format(
    'SET LOCAL "request.jwt.claim.sub"=%L',v_actor::text));
  PERFORM dblink_exec('identity_a','RESET ROLE');   -- #151: kernen er privat; kaldes som server
  SELECT version INTO v_version FROM dblink('identity_a',
    'SELECT private.decide_source_persona_identity('
    || '''88000000-0000-0000-0000-000000000031'',-987650031,1,''accepted'','
    || '''{"basis":"web_detail","note":"A"}'',''human'')') AS t(version integer);
  PERFORM dblink_exec('identity_a','SET LOCAL ROLE authenticated');
  IF v_version<>2 THEN RAISE EXCEPTION 'FEJL: første identity-writer gav version %',v_version; END IF;

  PERFORM dblink_exec('identity_b','BEGIN');
  PERFORM dblink_exec('identity_b','SET LOCAL ROLE authenticated');
  PERFORM dblink_exec('identity_b',format(
    'SET LOCAL "request.jwt.claim.sub"=%L',v_actor::text));
  PERFORM dblink_exec('identity_b','RESET ROLE');   -- #151: kernen er privat; kaldes som server
  PERFORM dblink_send_query('identity_b',
    'SELECT private.decide_source_persona_identity('
    || '''88000000-0000-0000-0000-000000000031'',-987650032,1,''accepted'','
    || '''{"basis":"web_detail","note":"B"}'',''human'')');
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP
    EXIT WHEN v_a_pid=ANY(pg_blocking_pids(v_b_pid));
    SELECT dblink_is_busy('identity_b') INTO v_busy;
    IF v_busy=0 OR clock_timestamp()>v_deadline THEN
      RAISE EXCEPTION 'FEJL: anden identity-writer blev ikke serialiseret på persona';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  PERFORM dblink_exec('identity_a','COMMIT');
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP
    SELECT dblink_is_busy('identity_b') INTO v_busy;
    EXIT WHEN v_busy=0;
    IF clock_timestamp()>v_deadline THEN
      RAISE EXCEPTION 'FEJL: anden identity-writer afsluttede ikke efter COMMIT';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  v_error:=NULL;
  BEGIN
    PERFORM * FROM dblink_get_result('identity_b') AS t(version integer);
  EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
  BEGIN
    PERFORM * FROM dblink_get_result('identity_b') AS t(version integer);
  EXCEPTION WHEN others THEN IF v_error IS NULL THEN v_error:=SQLERRM; END IF; END;
  IF v_error NOT LIKE '%EVIDENCE_IDENTITY_VERSION_CONFLICT%' THEN
    RAISE EXCEPTION 'FEJL: tabende identity-writer fejlede ikke fail-closed: %',v_error;
  END IF;
  PERFORM dblink_exec('identity_b','ROLLBACK');
  PERFORM dblink_disconnect('identity_a'); v_a_connected:=false;
  PERFORM dblink_disconnect('identity_b'); v_b_connected:=false;
  IF NOT EXISTS (
    SELECT 1 FROM private.source_persona_identity
     WHERE source_persona_id=v_persona AND canonical_person_id=-987650031
       AND decision_status='accepted' AND version=2
  ) OR (SELECT count(*) FROM private.source_persona_identity
         WHERE source_persona_id=v_persona)<>1 THEN
    RAISE EXCEPTION 'FEJL: samtidighed efterlod ikke præcis ét vindende identitetsmål';
  END IF;
  PERFORM dblink_exec('identity_setup',v_cleanup);
  PERFORM dblink_disconnect('identity_setup'); v_setup_connected:=false;
  PERFORM set_config('daa.verify_dblink_identity','executed',false);
  RAISE NOTICE 'OK: identitetsafgørelser serialiseres og expected_version er fail-closed';
EXCEPTION WHEN others THEN
  IF v_a_connected THEN
    BEGIN PERFORM dblink_exec('identity_a','ROLLBACK'); EXCEPTION WHEN others THEN NULL; END;
    BEGIN PERFORM dblink_disconnect('identity_a'); EXCEPTION WHEN others THEN NULL; END;
  END IF;
  IF v_b_connected THEN
    BEGIN PERFORM dblink_exec('identity_b','ROLLBACK'); EXCEPTION WHEN others THEN NULL; END;
    BEGIN PERFORM dblink_disconnect('identity_b'); EXCEPTION WHEN others THEN NULL; END;
  END IF;
  IF v_setup_connected THEN
    BEGIN PERFORM dblink_exec('identity_setup',v_cleanup); EXCEPTION WHEN others THEN NULL; END;
    BEGIN PERFORM dblink_disconnect('identity_setup'); EXCEPTION WHEN others THEN NULL; END;
  END IF;
  RAISE;
END $identity_concurrency$;

-- To forskellige forslag til samme record/scheme-entry må ikke begge kunne
-- accepteres. Parent-recordlåsen serialiserer den første afgørelse.
DO $placement_concurrency$
DECLARE
  v_conn text := format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),
    split_part(current_setting('unix_socket_directories'),',',1));
  v_actor uuid := '11000000-0000-0000-0000-000000000071';
  v_a uuid := '99000000-0000-0000-0000-000000000071';
  v_b uuid := '99000000-0000-0000-0000-000000000072';
  v_a_pid integer; v_b_pid integer; v_busy integer; v_version integer;
  v_deadline timestamptz; v_error text;
  v_setup_connected boolean:=false; v_a_connected boolean:=false; v_b_connected boolean:=false;
  v_cleanup text := $cleanup$
    SET session_replication_role=replica;
    DELETE FROM private.source_record_placement_decision WHERE placement_id IN
      ('99000000-0000-0000-0000-000000000071','99000000-0000-0000-0000-000000000072');
    DELETE FROM private.source_record_placement WHERE id IN
      ('99000000-0000-0000-0000-000000000071','99000000-0000-0000-0000-000000000072');
    DELETE FROM lineage_scheme_entry WHERE id=-987650071;
    DELETE FROM lineage_scheme WHERE id=-987650071;
    DELETE FROM slaegt WHERE id=-987650071;
    DELETE FROM private.source_observation WHERE id='66000000-0000-0000-0000-000000000071';
    DELETE FROM private.source_record_anchor_event WHERE occurrence_id='55000000-0000-0000-0000-000000000071';
    DELETE FROM private.source_record_occurrence WHERE id='55000000-0000-0000-0000-000000000071';
    DELETE FROM private.source_record WHERE id='77000000-0000-0000-0000-000000000071';
    DELETE FROM private.source_rendition WHERE id='33000000-0000-0000-0000-000000000071';
    DELETE FROM private.extraction_run WHERE id='22000000-0000-0000-0000-000000000071';
    DELETE FROM source WHERE id=-987650071;
    DELETE FROM profiles WHERE id='11000000-0000-0000-0000-000000000071';
    DELETE FROM auth.users WHERE id='11000000-0000-0000-0000-000000000071';
    SET session_replication_role=origin;
  $cleanup$;
BEGIN
  IF to_regprocedure('dblink_connect(text,text)') IS NULL THEN
    RAISE EXCEPTION 'DB_VERIFY_DBLINK_REQUIRED: placement-samtidighed';
  END IF;
  PERFORM dblink_connect('placement_setup',v_conn||' application_name=daa_verify_placement_setup');
  v_setup_connected:=true; PERFORM dblink_exec('placement_setup',v_cleanup);
  PERFORM dblink_exec('placement_setup',format(
    'INSERT INTO auth.users(id,email) VALUES (%L,%L)',v_actor,'placement-lock@test.invalid'));
  PERFORM dblink_exec('placement_setup',format(
    'INSERT INTO profiles(id,rolle,email,navn) VALUES (%L,''redaktion'',%L,''Placement Editor'')',
    v_actor,'placement-lock@test.invalid'));
  PERFORM dblink_exec('placement_setup',
    'INSERT INTO source(id,titel,import_key) VALUES (-987650071,''Placement lock'',''verify:placement:lock'')');
  PERFORM dblink_exec('placement_setup',
    'INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) '
    || 'VALUES (''22000000-0000-0000-0000-000000000071'',-987650071,''placement-lock-run'',''1.0'',''verify'',''verify'','
    || quote_literal(repeat('7',64)) || ',''{}'')');
  PERFORM dblink_exec('placement_setup',
    'INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata) '
    || 'VALUES (''33000000-0000-0000-0000-000000000071'',-987650071,''placement-lock-rendition'',''text_layer'','
    || quote_literal(repeat('8',64)) || ',''{}'')');
  PERFORM dblink_exec('placement_setup',
    'INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id) VALUES '
    || '(''77000000-0000-0000-0000-000000000071'',-987650071,''placement-lock-record'',''person'','
    || '''22000000-0000-0000-0000-000000000071'')');
  PERFORM dblink_exec('placement_setup',
    'INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id) VALUES '
    || '(''55000000-0000-0000-0000-000000000071'',''33000000-0000-0000-0000-000000000071'',''placement-lock-occurrence'',1,1,0,6,''Header'',''placement-physical'',''placement-structural'',''22000000-0000-0000-0000-000000000071'')');
  PERFORM dblink_exec('placement_setup',
    'INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name) VALUES '
    || '(''55000000-0000-0000-0000-000000000071'',''77000000-0000-0000-0000-000000000071'',''accepted'',''{"basis":"verify"}'',1,'
    || quote_literal(v_actor) || ',''Placement Editor'')');
  PERFORM dblink_exec('placement_setup',
    'INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id) VALUES '
    || '(''66000000-0000-0000-0000-000000000071'',''55000000-0000-0000-0000-000000000071'',''header'',1,1,0,6,''Header'',''clear'',''verify'',''22000000-0000-0000-0000-000000000071'')');
  PERFORM dblink_exec('placement_setup',
    'INSERT INTO slaegt(id,navn,sorteringsnavn,slug) VALUES (-987650071,''Placement Family'',''placement family'',''placement-family-verify'')');
  PERFORM dblink_exec('placement_setup',
    'INSERT INTO lineage_scheme(id,slaegt_id,source_id,kind,label) VALUES (-987650071,-987650071,-987650071,''stamtavle'',''Placement verify'')');
  PERFORM dblink_exec('placement_setup',
    'INSERT INTO lineage_scheme_entry(id,scheme_id,slaegt_id,code,label,sort_order) VALUES (-987650071,-987650071,-987650071,''I'',''I'',1)');
  PERFORM dblink_exec('placement_setup','BEGIN');
  PERFORM dblink_exec('placement_setup',format(
    'INSERT INTO private.source_record_placement(id,source_record_id,scheme_entry_id,header_observation_id) VALUES (%L,''77000000-0000-0000-0000-000000000071'',-987650071,''66000000-0000-0000-0000-000000000071''),(%L,''77000000-0000-0000-0000-000000000071'',-987650071,''66000000-0000-0000-0000-000000000071'')',v_a,v_b));
  PERFORM dblink_exec('placement_setup',format(
    'INSERT INTO private.source_record_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name) VALUES (%L,1,''proposed'',''{"basis":"A"}'',''ingest'',''verify ingest''),(%L,1,''proposed'',''{"basis":"B"}'',''ingest'',''verify ingest'')',v_a,v_b));
  PERFORM dblink_exec('placement_setup','COMMIT');

  PERFORM dblink_connect('placement_a',v_conn||' application_name=daa_verify_placement_a'); v_a_connected:=true;
  PERFORM dblink_connect('placement_b',v_conn||' application_name=daa_verify_placement_b'); v_b_connected:=true;
  SELECT pid INTO v_a_pid FROM dblink('placement_a','SELECT pg_backend_pid()') AS t(pid integer);
  SELECT pid INTO v_b_pid FROM dblink('placement_b','SELECT pg_backend_pid()') AS t(pid integer);
  PERFORM dblink_exec('placement_a','BEGIN');
  PERFORM dblink_exec('placement_a','SET LOCAL ROLE authenticated');
  PERFORM dblink_exec('placement_a',format('SET LOCAL "request.jwt.claim.sub"=%L',v_actor::text));
  SELECT version INTO v_version FROM dblink('placement_a',format(
    'SELECT red_decide_source_record_placement(%L,1,''accepted'',''{"basis":"A"}'')',v_a)) AS t(version integer);
  IF v_version<>2 THEN RAISE EXCEPTION 'FEJL: første placement-writer gav version %',v_version; END IF;
  PERFORM dblink_exec('placement_b','BEGIN');
  PERFORM dblink_exec('placement_b','SET LOCAL ROLE authenticated');
  PERFORM dblink_exec('placement_b',format('SET LOCAL "request.jwt.claim.sub"=%L',v_actor::text));
  PERFORM dblink_send_query('placement_b',format(
    'SELECT red_decide_source_record_placement(%L,1,''accepted'',''{"basis":"B"}'')',v_b));
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP
    EXIT WHEN v_a_pid=ANY(pg_blocking_pids(v_b_pid));
    SELECT dblink_is_busy('placement_b') INTO v_busy;
    IF v_busy=0 OR clock_timestamp()>v_deadline THEN RAISE EXCEPTION 'FEJL: anden placement-writer blev ikke serialiseret'; END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  PERFORM dblink_exec('placement_a','COMMIT');
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP SELECT dblink_is_busy('placement_b') INTO v_busy; EXIT WHEN v_busy=0;
    IF clock_timestamp()>v_deadline THEN RAISE EXCEPTION 'FEJL: anden placement-writer afsluttede ikke'; END IF;
    PERFORM pg_sleep(0.02); END LOOP;
  v_error:=NULL;
  BEGIN PERFORM * FROM dblink_get_result('placement_b') AS t(version integer);
  EXCEPTION WHEN others THEN v_error:=SQLERRM; END;
  BEGIN PERFORM * FROM dblink_get_result('placement_b') AS t(version integer);
  EXCEPTION WHEN others THEN IF v_error IS NULL THEN v_error:=SQLERRM; END IF; END;
  IF v_error NOT LIKE '%EVIDENCE_PLACEMENT_ALREADY_ACCEPTED%' THEN
    RAISE EXCEPTION 'FEJL: tabende placement-writer fejlede ikke fail-closed: %',v_error; END IF;
  PERFORM dblink_exec('placement_b','ROLLBACK');
  PERFORM dblink_disconnect('placement_a'); v_a_connected:=false;
  PERFORM dblink_disconnect('placement_b'); v_b_connected:=false;
  IF (SELECT count(*) FROM private.source_record_placement_current
       WHERE source_record_id='77000000-0000-0000-0000-000000000071'
         AND scheme_entry_id=-987650071 AND decision_status='accepted')<>1
     OR EXISTS(SELECT 1 FROM private.source_record_placement_decision WHERE placement_id=v_b AND version=2) THEN
    RAISE EXCEPTION 'FEJL: placement-race efterlod ikke præcis én accepted decision'; END IF;
  PERFORM dblink_exec('placement_setup',v_cleanup);
  PERFORM dblink_disconnect('placement_setup'); v_setup_connected:=false;
  PERFORM set_config('daa.verify_dblink_placement','executed',false);
  RAISE NOTICE 'OK: placement-afgørelser serialiseres på parent-record og er globalt entydige';
EXCEPTION WHEN others THEN
  IF v_a_connected THEN BEGIN PERFORM dblink_exec('placement_a','ROLLBACK'); EXCEPTION WHEN others THEN NULL; END;
    BEGIN PERFORM dblink_disconnect('placement_a'); EXCEPTION WHEN others THEN NULL; END; END IF;
  IF v_b_connected THEN BEGIN PERFORM dblink_exec('placement_b','ROLLBACK'); EXCEPTION WHEN others THEN NULL; END;
    BEGIN PERFORM dblink_disconnect('placement_b'); EXCEPTION WHEN others THEN NULL; END; END IF;
  IF v_setup_connected THEN BEGIN PERFORM dblink_exec('placement_setup',v_cleanup); EXCEPTION WHEN others THEN NULL; END;
    BEGIN PERFORM dblink_disconnect('placement_setup'); EXCEPTION WHEN others THEN NULL; END; END IF;
  RAISE;
END $placement_concurrency$;

-- Task 11: køens fire RPC'er må kun være tilgængelige gennem authenticated.
DO $source_persona_queue_verify$
BEGIN
  IF to_regprocedure('public.red_source_persona_queue(text,bigint,uuid,integer,text)') IS NULL
     OR to_regprocedure('public.red_source_persona_detail(uuid)') IS NULL
     OR to_regprocedure('public.red_source_persona_history(uuid)') IS NULL
     OR to_regprocedure('public.red_afgoer_source_persona(uuid,integer,text,bigint,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'FEJL: Task 11 mangler source-persona-køens RPCer';
  END IF;
  IF has_function_privilege('anon','public.red_source_persona_queue(text,bigint,uuid,integer,text)','EXECUTE')
     OR has_function_privilege('anon','public.red_source_persona_detail(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.red_source_persona_history(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.red_afgoer_source_persona(uuid,integer,text,bigint,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'FEJL: Task 11 eksponerer privat source-persona-kø for anon';
  END IF;
  RAISE NOTICE 'OK: Task 11 source-persona-kø er privat og har eksplicitte RPC-kontrakter';
END $source_persona_queue_verify$;

-- ===== Person OCR kvalitetsark — atomisk rettelse og historik =====
-- Selvstændig transaktionsfixture. Alle positive og negative veje kører gennem
-- den offentlige SECURITY DEFINER-flade, og blokken ruller altid tilbage.
DO $$
DECLARE
  v_redaktor uuid := '00000000-0000-0000-0000-0000000000c4';
  v_row jsonb; v_hist record; v_cs_date bigint; v_journal_id bigint;
  v_name_assertion bigint := -987655301; v_birth_assertion bigint := -987655302;
  v_death_assertion bigint := -987655303; v_citation_id bigint := -987655501;
  v_before_journal int; v_before_events int; v_before_assertions int;
  v_before_conclusions int; v_before_name text; v_before_gender text; v_koen_fingerprint text;
  v_fresh_fingerprint text; v_frozen_fingerprint text; v_name_events int; v_name_history int;
  v_member_blocked boolean := false; v_anon_blocked boolean := false;
  v_hist_member_blocked boolean := false; v_hist_anon_blocked boolean := false;
  v_hist_count int; v_first_after jsonb; v_second_after jsonb;
  v_original_import jsonb;
BEGIN
  INSERT INTO source(id,titel,import_key) VALUES
    (-987655101,'OCR rette-fixture','verify:ocr:write'),
    (-987655102,'Forkert OCR-kilde','verify:ocr:other'),
    (-987655103,'Ekstra importanker','verify:ocr:extra');
  INSERT INTO person(id,koen) VALUES
    (-987655111,'mand'), (-987655112,'kvinde'), (-987655113,'mand'),
    (-987655114,'ukendt');
  INSERT INTO person_external_id(person_id,source_id,record_key) VALUES
    (-987655111,-987655101,'I-15a'),
    (-987655112,-987655101,'I-16'),
    (-987655113,-987655101,'I-17'),
    (-987655113,-987655103,'I-17-extra'),
    (-987655114,-987655101,'I-18');
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES
    (-987655201,'person',-987655111,'navn'),
    (-987655202,'person',-987655111,'fødsel'),
    (-987655203,'person',-987655111,'død'),
    (-987655204,'person',-987655112,'navn'),
    (-987655205,'person',-987655114,'navn'),
    (-987655206,'person',-987655114,'navn');
  INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,date_raw,date_min,date_max,
                        date_qualifier,calendar,date_certainty,uforanderlig) VALUES
    (v_name_assertion,'fact',-987655201,'Mikkel OCR',NULL,NULL,NULL,NULL,'gregoriansk',NULL,true),
    (v_birth_assertion,'fact',-987655202,NULL,'1644-06-11','1644-06-11','1644-06-11','exact','gregoriansk',NULL,true),
    (v_death_assertion,'fact',-987655203,NULL,'1700-01-01','1700-01-01','1700-01-01','exact','gregoriansk',NULL,true),
    (-987655304,'fact',-987655204,'Forkert kilde',NULL,NULL,NULL,NULL,'gregoriansk',NULL,true),
    (-987655305,'fact',-987655205,'Flertydig A',NULL,NULL,NULL,NULL,'gregoriansk',NULL,true),
    (-987655306,'fact',-987655206,'Flertydig B',NULL,NULL,NULL,NULL,'gregoriansk',NULL,true);
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status) VALUES
    (-987655401,'fact',-987655201,v_name_assertion,'afklaret'),
    (-987655402,'fact',-987655202,v_birth_assertion,'afklaret'),
    (-987655403,'fact',-987655203,v_death_assertion,'afklaret'),
    (-987655404,'fact',-987655204,-987655304,'afklaret'),
    (-987655405,'fact',-987655205,-987655305,'afklaret');
  -- A second selected fact makes the fourth person fail closed as ambiguous.
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status)
    VALUES (-987655406,'fact',-987655206,-987655306,'afklaret');
  INSERT INTO citation(id,assertion_id,source_id,side,citat_tekst) VALUES
    (v_citation_id,v_name_assertion,-987655101,'42','Mikkel OCR'),
    (-987655502,v_birth_assertion,-987655101,'42','født 1644-06-11'),
    (-987655503,v_death_assertion,-987655101,'42','død 1700-01-01'),
    (-987655504,-987655304,-987655102,'42','Forkert kilde'),
    (-987655505,-987655305,-987655101,'42','Flertydig A'),
    (-987655506,-987655306,-987655101,'42','Flertydig B');

  -- Fixed SQL vector is independent of the new helper and must remain in Task 2 parity.
  IF ocr_input_fingerprint('verify:ocr:write','I-15a','foedsel',
       '{"raw":"1644-06-11","min":"1644-06-11","max":"1644-06-11","qualifier":"exact","calendar":"gregoriansk","certainty":null}'::jsonb,
       'født 1644-06-11') IS NULL THEN
    RAISE EXCEPTION 'FEJL: OCR-fingerprint-vektor kunne ikke beregnes';
  END IF;

  -- Execute ACL and internal role guards are independently observable.
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','navn','x',NULL,'godkendt');
  EXCEPTION WHEN insufficient_privilege THEN v_anon_blocked := true;
  END;
  BEGIN
    PERFORM * FROM red_ocr_historik('verify:ocr:write','I-15a','navn');
  EXCEPTION WHEN insufficient_privilege THEN v_hist_anon_blocked := true;
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub','',true);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','navn','x',NULL,'godkendt');
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'OCR_ROLE_FORBIDDEN%' THEN v_member_blocked := true; ELSE RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM red_ocr_historik('verify:ocr:write','I-15a','navn');
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'OCR_ROLE_FORBIDDEN%' THEN v_hist_member_blocked := true; ELSE RAISE; END IF;
  END;
  RESET ROLE;
  IF NOT v_anon_blocked OR NOT v_hist_anon_blocked OR NOT v_member_blocked OR NOT v_hist_member_blocked THEN
    RAISE EXCEPTION 'FEJL: OCR-RPC ACL/rolle-gate anon=%/% medlem=%/%',
      v_anon_blocked,v_hist_anon_blocked,v_member_blocked,v_hist_member_blocked;
  END IF;

  INSERT INTO auth.users(id,email) VALUES (v_redaktor,'ocr-write-verify@test.invalid');
  INSERT INTO profiles(id,rolle,navn,email) VALUES
    (v_redaktor,'redaktion','OCR Verify Actor','ocr-write-verify@test.invalid');
  PERFORM set_config('request.jwt.claim.sub',v_redaktor::text,true);
  SET LOCAL ROLE authenticated;

  -- First and repeated name correction: one logical journal row keeps original import/fingerprint.
  SELECT input_fingerprint->>'navn', importeret->'navn' INTO STRICT v_before_name, v_original_import
    FROM red_person_grid() WHERE person_id=-987655111;
  v_row := red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','navn',v_before_name,
    '{"value":"Mikkel Rettet"}'::jsonb,'rettet','må ikke vinde');
  IF v_row->>'person_id' <> '-987655111' OR (SELECT vaerdi_tekst FROM assertion WHERE id=v_name_assertion) <> 'Mikkel Rettet' THEN
    RAISE EXCEPTION 'FEJL: navnerettelse returnerede ikke den friske, rettede række';
  END IF;
  SELECT id INTO v_journal_id FROM import_korrektion
    WHERE import_key='verify:ocr:write' AND record_key='I-15a' AND felt='navn';
  IF v_journal_id IS NULL OR (SELECT actor_id FROM import_korrektion WHERE id=v_journal_id) <> v_redaktor
     OR (SELECT actor_navn FROM import_korrektion WHERE id=v_journal_id) <> 'OCR Verify Actor' THEN
    RAISE EXCEPTION 'FEJL: navnejournal mangler autentisk aktør';
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  v_row := red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','navn',v_before_name,
    '{"value":"Mikkel Rettet Igen"}'::jsonb,'rettet','fallback');
  IF (SELECT count(*) FROM import_korrektion WHERE import_key='verify:ocr:write' AND record_key='I-15a' AND felt='navn') <> 1
     OR (SELECT id FROM import_korrektion WHERE import_key='verify:ocr:write' AND record_key='I-15a' AND felt='navn') <> v_journal_id
     OR (SELECT importeret FROM import_korrektion WHERE id=v_journal_id) <> v_original_import
     OR (SELECT korrigeret FROM import_korrektion WHERE id=v_journal_id) <> '{"value":"Mikkel Rettet Igen"}'::jsonb
     OR (SELECT vaerdi_tekst FROM assertion WHERE id=v_name_assertion) <> 'Mikkel Rettet Igen' THEN
    RAISE EXCEPTION 'FEJL: gentagen OCR-rettelse drev import-snapshot eller journalidentitet';
  END IF;
  SELECT input_fingerprint INTO v_frozen_fingerprint FROM import_korrektion WHERE id=v_journal_id;
  IF v_frozen_fingerprint <> v_before_name THEN
    RAISE EXCEPTION 'FEJL: gentagen OCR-rettelse ændrede frosset source-fingerprint';
  END IF;
  -- A newly projected fingerprint after source-context drift must not bless a stale journal.
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  UPDATE citation SET citat_tekst='Mikkel OCR ændret kildekontekst' WHERE id=v_citation_id;
  SET LOCAL ROLE authenticated;
  SELECT input_fingerprint->>'navn' INTO v_fresh_fingerprint FROM red_person_grid() WHERE person_id=-987655111;
  RESET ROLE;
  SELECT count(*) INTO v_name_events FROM change_event;
  SELECT count(*) INTO v_name_history FROM red_ocr_historik('verify:ocr:write','I-15a','navn');
  BEGIN
    PERFORM red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','navn',v_fresh_fingerprint,
      '{"value":"må ikke gemmes"}'::jsonb);
    RAISE EXCEPTION 'FEJL: frisk fingerprint efter kildeændring blev accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'OCR_FINGERPRINT_STALE%' THEN RAISE; END IF; END;
  IF (SELECT input_fingerprint FROM import_korrektion WHERE id=v_journal_id) <> v_frozen_fingerprint
     OR (SELECT vaerdi_tekst FROM assertion WHERE id=v_name_assertion) <> 'Mikkel Rettet Igen'
     OR (SELECT count(*) FROM change_event) <> v_name_events
     OR (SELECT count(*) FROM red_ocr_historik('verify:ocr:write','I-15a','navn')) <> v_name_history THEN
    RAISE EXCEPTION 'FEJL: stale kildekontekst ændrede journal, model eller historik';
  END IF;
  IF EXISTS (SELECT 1 FROM assertion WHERE id NOT IN (v_name_assertion,v_birth_assertion,v_death_assertion,-987655304,-987655305,-987655306)
             AND target_id IN (-987655201,-987655202,-987655203))
     OR (SELECT count(*) FROM conclusion WHERE target_id IN (-987655201,-987655202,-987655203)) <> 3
     OR (SELECT source_id FROM citation WHERE id=v_citation_id) <> -987655101
     OR NOT (SELECT uforanderlig FROM assertion WHERE id=v_name_assertion) THEN
    RAISE EXCEPTION 'FEJL: OCR-navnerettelse ændrede evidensidentitet';
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);

  -- Date touches only the one selected assertion's date fields, and the normal trigger regenerates the cache.
  SELECT input_fingerprint->>'foedsel' INTO STRICT v_before_name FROM red_person_grid() WHERE person_id=-987655111;
  v_row := red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','foedsel',v_before_name,
    '{"raw":"1644-06-12","min":"1644-06-12","max":"1644-06-12","qualifier":"exact","calendar":"gregoriansk","certainty":null}'::jsonb);
  v_cs_date := current_setting('app.change_set_id')::bigint;
  IF (SELECT date_raw FROM assertion WHERE id=v_birth_assertion) <> '1644-06-12'
     OR (SELECT date_min FROM assertion WHERE id=v_birth_assertion) <> date '1644-06-12'
     OR (SELECT vaerdi_tekst FROM assertion WHERE id=v_birth_assertion) IS NOT NULL
     OR (SELECT date_raw FROM assertion WHERE id=v_death_assertion) <> '1700-01-01' THEN
    RAISE EXCEPTION 'FEJL: datorettelse ramte ikke kun den valgte assertion';
  END IF;
  PERFORM red_fortryd_change_set(v_cs_date,false);
  IF (SELECT date_raw FROM assertion WHERE id=v_birth_assertion) <> '1644-06-11'
     OR EXISTS (SELECT 1 FROM import_korrektion WHERE import_key='verify:ocr:write' AND record_key='I-15a' AND felt='foedsel') THEN
    RAISE EXCEPTION 'FEJL: fortryd genskabte ikke OCR-dato og journal';
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);

  -- Gender is the sole model mutation for gender; approve/defer never mutate the model.
  SELECT input_fingerprint->>'koen', koen INTO STRICT v_before_name,v_before_gender FROM red_person_grid() WHERE person_id=-987655111;
  v_row := red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','koen',v_before_name,
    '{"value":"kvinde"}'::jsonb);
  IF (SELECT koen FROM person WHERE id=-987655111) <> 'kvinde'
     OR (SELECT vaerdi_tekst FROM assertion WHERE id=v_name_assertion) <> 'Mikkel Rettet Igen' THEN
    RAISE EXCEPTION 'FEJL: kønsrettelse rørte andet end person.koen';
  END IF;
  SELECT input_fingerprint->>'koen' INTO STRICT v_before_name FROM red_person_grid() WHERE person_id=-987655111;
  PERFORM red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','koen',v_before_name,NULL,'godkendt');
  PERFORM red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','koen',v_before_name,NULL,'udskudt');
  IF (SELECT koen FROM person WHERE id=-987655111) <> 'kvinde'
     OR (SELECT status FROM import_korrektion WHERE import_key='verify:ocr:write' AND record_key='I-15a' AND felt='koen') <> 'udskudt'
     OR (SELECT korrigeret FROM import_korrektion WHERE import_key='verify:ocr:write' AND record_key='I-15a' AND felt='koen') <> '{"value":"kvinde"}'::jsonb THEN
    RAISE EXCEPTION 'FEJL: godkend/udskyd ændrede model eller journalstatus forkert';
  END IF;

  -- History is scoped to the one logical journal PK and frozen, newest first snapshots.
  SELECT count(*) INTO v_hist_count FROM red_ocr_historik('verify:ocr:write','I-15a','navn');
  SELECT h.efter INTO v_first_after FROM red_ocr_historik('verify:ocr:write','I-15a','navn') h LIMIT 1;
  SELECT h.efter INTO v_second_after FROM red_ocr_historik('verify:ocr:write','I-15a','navn') h OFFSET 1 LIMIT 1;
  IF v_hist_count <> 2 OR v_first_after->>'korrigeret' IS NULL OR v_second_after->>'importeret' IS NULL
     OR EXISTS (SELECT 1 FROM red_ocr_historik('verify:ocr:write','I-15a','doed')) THEN
    RAISE EXCEPTION 'FEJL: OCR-historik er ikke isoleret eller komplet';
  END IF;

  -- Every negative path is atomic: counts and model values remain exactly as before.
  RESET ROLE;
  SELECT count(*) INTO v_before_journal FROM import_korrektion;
  SELECT count(*) INTO v_before_events FROM change_event;
  SELECT count(*) INTO v_before_assertions FROM assertion;
  SELECT count(*) INTO v_before_conclusions FROM conclusion;
  SELECT vaerdi_tekst INTO v_before_name FROM assertion WHERE id=v_name_assertion;
  SELECT koen INTO v_before_gender FROM person WHERE id=-987655111;
  BEGIN PERFORM red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','ukendt','x',NULL,'godkendt');
    RAISE EXCEPTION 'FEJL: ukendt felt blev accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'OCR_FIELD_INVALID%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','koen','forkert',NULL,'godkendt');
    RAISE EXCEPTION 'FEJL: stale fingerprint blev accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'OCR_FINGERPRINT_STALE%' THEN RAISE; END IF; END;
  SELECT input_fingerprint->>'koen' INTO v_koen_fingerprint FROM red_person_grid() WHERE person_id=-987655111;
  BEGIN PERFORM red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','koen',v_koen_fingerprint,'{"value":"andet"}'::jsonb);
    RAISE EXCEPTION 'FEJL: ugyldigt køn blev accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'OCR_VALUE_INVALID%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','navn',(SELECT input_fingerprint->>'navn' FROM red_person_grid() WHERE person_id=-987655111),NULL);
    RAISE EXCEPTION 'FEJL: manglende rettelse blev accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'OCR_VALUE_INVALID%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_ret_ocr_felt(-987655113,'verify:ocr:write','I-17','koen','x',NULL,'godkendt');
    RAISE EXCEPTION 'FEJL: flere importankre blev accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'OCR_IMPORT_ANCHOR_AMBIGUOUS%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_ret_ocr_felt(-987655114,'verify:ocr:write','I-18','navn','x',NULL,'godkendt');
    RAISE EXCEPTION 'FEJL: flere assertion-kandidater blev accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'OCR_ASSERTION_AMBIGUOUS%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_ret_ocr_felt(-987655112,'verify:ocr:write','I-16','navn','x',NULL,'godkendt');
    RAISE EXCEPTION 'FEJL: source mismatch blev accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'OCR_ASSERTION_AMBIGUOUS%' THEN RAISE; END IF; END;
  IF (SELECT count(*) FROM import_korrektion) <> v_before_journal
     OR (SELECT count(*) FROM change_event) <> v_before_events
     OR (SELECT count(*) FROM assertion) <> v_before_assertions
     OR (SELECT count(*) FROM conclusion) <> v_before_conclusions
     OR (SELECT vaerdi_tekst FROM assertion WHERE id=v_name_assertion) <> v_before_name
     OR (SELECT koen FROM person WHERE id=-987655111) <> v_before_gender THEN
    RAISE EXCEPTION 'FEJL: negativ OCR-vej var ikke atomisk journal=%/% event=%/% assertion=%/% conclusion=%/% navn=%/% koen=%/%',
      (SELECT count(*) FROM import_korrektion),v_before_journal,(SELECT count(*) FROM change_event),v_before_events,
      (SELECT count(*) FROM assertion),v_before_assertions,(SELECT count(*) FROM conclusion),v_before_conclusions,
      (SELECT vaerdi_tekst FROM assertion WHERE id=v_name_assertion),v_before_name,
      (SELECT koen FROM person WHERE id=-987655111),v_before_gender;
  END IF;
  RESET ROLE;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: Person OCR kvalitetsark — atomisk rettelse, historik, undo og roller';
  ELSE RAISE; END IF;
END $$;

-- ===== Person OCR kvalitetsark — reel to-forbindelses låseorden =====
-- dblink er bevidst kun et VERIFY-hjælpemiddel. En produktionsbase uden extension
-- springer over; den lokale disposable gate aktiverer den og kører den reelle cyklus.
DO $$
DECLARE
  v_uid uuid := '00000000-0000-0000-0000-0000000000c6';
  v_conn text := format(
    'dbname=%s port=%s host=%s', current_database(), current_setting('port'),
    split_part(current_setting('unix_socket_directories'),',',1)
  );
  v_a_busy integer;
  v_b_busy integer;
  v_a_pid integer;
  v_b_pid integer;
  v_locked bigint;
  v_result bigint;
  v_deleted bigint;
  v_deadline timestamptz;
  v_a_async boolean := false;
  v_b_async boolean := false;
  v_a_in_tx boolean := false;
  v_b_in_tx boolean := false;
  v_error_state text;
  v_error_message text;
  v_cleanup_error text;
  v_cleanup_sql text := $cleanup_sql$
    DO $remote_cleanup$
    BEGIN
      DELETE FROM change_event WHERE change_set_id IN (
        SELECT id FROM change_set
        WHERE operation='red_slet_person' AND subjekt_type='person' AND subjekt_id=-987654611
      );
      DELETE FROM change_set
        WHERE operation='red_slet_person' AND subjekt_type='person' AND subjekt_id=-987654611;
      DELETE FROM import_korrektion
        WHERE import_key='verify:ocr:lock' AND record_key='I-lock';
      DELETE FROM citation WHERE id=-987654951;
      DELETE FROM conclusion WHERE id=-987654901;
      DELETE FROM assertion WHERE id=-987654801;
      DELETE FROM fact WHERE id=-987654701;
      DELETE FROM person_external_id WHERE person_id=-987654611 AND source_id=-987654601;
      DELETE FROM profiles WHERE id='00000000-0000-0000-0000-0000000000c6';
      DELETE FROM auth.users WHERE id='00000000-0000-0000-0000-0000000000c6';
      DELETE FROM person WHERE id=-987654611;
      DELETE FROM source WHERE id=-987654601;
    END $remote_cleanup$
  $cleanup_sql$;
BEGIN
  IF to_regprocedure('dblink_connect(text,text)') IS NULL THEN
    RAISE EXCEPTION 'DB_VERIFY_DBLINK_REQUIRED: OCR-låseorden';
  END IF;
  -- Setup is committed through a third local connection: dblink sessions cannot see
  -- uncommitted rows from this verify DO-block.
  PERFORM dblink_connect('ocr_lock_setup',v_conn || ' application_name=daa_verify_ocr_lock_setup');
  PERFORM dblink_exec('ocr_lock_setup','INSERT INTO source(id,titel,import_key) VALUES (-987654601,''OCR lock verify'',''verify:ocr:lock'') ON CONFLICT (id) DO UPDATE SET titel=excluded.titel');
  PERFORM dblink_exec('ocr_lock_setup','INSERT INTO person(id) VALUES (-987654611) ON CONFLICT (id) DO NOTHING');
  PERFORM dblink_exec('ocr_lock_setup','INSERT INTO person_external_id(person_id,source_id,record_key) VALUES (-987654611,-987654601,''I-lock'') ON CONFLICT DO NOTHING');
  PERFORM dblink_exec('ocr_lock_setup','INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-987654701,''person'',-987654611,''navn'') ON CONFLICT DO NOTHING');
  PERFORM dblink_exec('ocr_lock_setup','INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst) VALUES (-987654801,''fact'',-987654701,''Lock'') ON CONFLICT DO NOTHING');
  PERFORM dblink_exec('ocr_lock_setup','INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status) VALUES (-987654901,''fact'',-987654701,-987654801,''afklaret'') ON CONFLICT DO NOTHING');
  PERFORM dblink_exec('ocr_lock_setup','INSERT INTO citation(id,assertion_id,source_id,citat_tekst) VALUES (-987654951,-987654801,-987654601,''Lock'') ON CONFLICT DO NOTHING');
  PERFORM dblink_exec('ocr_lock_setup',format('INSERT INTO auth.users(id,email) VALUES (''%s'',''ocr-lock-verify@test.invalid'') ON CONFLICT (id) DO NOTHING',v_uid));
  PERFORM dblink_exec('ocr_lock_setup',format('INSERT INTO profiles(id,rolle,email) VALUES (''%s'',''redaktion'',''ocr-lock-verify@test.invalid'') ON CONFLICT (id) DO UPDATE SET rolle=''redaktion''',v_uid));
  PERFORM dblink_connect('ocr_lock_a',v_conn || ' application_name=daa_verify_ocr_lock_a');
  PERFORM dblink_connect('ocr_lock_b',v_conn || ' application_name=daa_verify_ocr_lock_b');
  SELECT pid INTO v_a_pid
    FROM dblink('ocr_lock_a','SELECT pg_backend_pid()') AS t(pid integer);
  SELECT pid INTO v_b_pid
    FROM dblink('ocr_lock_b','SELECT pg_backend_pid()') AS t(pid integer);
  IF v_a_pid IS NULL OR v_b_pid IS NULL THEN
    RAISE EXCEPTION 'FEJL: OCR-låseorden kunne ikke observere backend-PID';
  END IF;

  -- A acquires both stable-anchor row locks synchronously. B is not started until this
  -- real lock operation has returned, so the intended interleaving has no timer race.
  PERFORM dblink_exec('ocr_lock_a','BEGIN');
  v_a_in_tx := true;
  PERFORM dblink_exec('ocr_lock_a','SET LOCAL statement_timeout=''10s''');
  SELECT locked INTO v_locked FROM dblink('ocr_lock_a',
    'SELECT count(*)::bigint FROM ('
    || 'SELECT s.id FROM source s JOIN person_external_id pei ON pei.source_id=s.id '
    || 'WHERE pei.person_id=-987654611 FOR UPDATE OF s,pei'
    || ') locked') AS t(locked bigint);
  IF v_locked IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'FEJL: OCR-låseorden A låste ikke source/external-id, antal=%',v_locked;
  END IF;

  PERFORM dblink_exec('ocr_lock_b','BEGIN');
  v_b_in_tx := true;
  PERFORM dblink_exec('ocr_lock_b','SET LOCAL statement_timeout=''10s''');
  PERFORM * FROM dblink('ocr_lock_b',format(
    'SELECT set_config(''request.jwt.claim.sub'',''%s'',true)',v_uid)) AS t(value text);
  PERFORM dblink_send_query('ocr_lock_b',
    'SELECT count(*)::bigint AS deleted FROM (SELECT red_slet_person(-987654611)) s');
  v_b_async := true;

  -- The barrier is behavior, not elapsed time: B must be waiting behind A's backend
  -- before A reaches citation. With the old inverse order B already owns citation here,
  -- so A's next statement recreates the deadlock; with the fixed order A can proceed.
  v_deadline := clock_timestamp() + interval '3 seconds';
  LOOP
    EXIT WHEN v_a_pid = ANY(pg_blocking_pids(v_b_pid));
    SELECT dblink_is_busy('ocr_lock_b') INTO v_b_busy;
    IF v_b_busy = 0 THEN
      RAISE EXCEPTION 'FEJL: OCR-låseorden B nåede ikke blocker-barrieren';
    END IF;
    IF clock_timestamp() > v_deadline THEN
      RAISE EXCEPTION 'FEJL: OCR-låseorden observerede ikke B blokeret af A';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  -- Kept as an executable failure-mode test: at this point A owns the anchor locks
  -- and B is actively waiting, so the exception path must roll back/disconnect both.
  IF current_setting('daa.verify_force_ocr_lock_failure',true) = 'on' THEN
    RAISE EXCEPTION 'FORCED_OCR_LOCK_VERIFY_FAILURE';
  END IF;

  PERFORM dblink_send_query('ocr_lock_a',
    'UPDATE citation SET citat_tekst=''A'' WHERE id=-987654951 RETURNING id');
  v_a_async := true;
  v_deadline := clock_timestamp() + interval '10 seconds';
  LOOP
    SELECT dblink_is_busy('ocr_lock_a') INTO v_a_busy;
    EXIT WHEN v_a_busy = 0;
    IF clock_timestamp() > v_deadline THEN
      RAISE EXCEPTION 'FEJL: OCR-låseorden A overskred 10 sekunder (mulig deadlock)';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  SELECT id INTO v_result FROM dblink_get_result('ocr_lock_a') AS t(id bigint);
  PERFORM * FROM dblink_get_result('ocr_lock_a') AS t(id bigint);
  v_a_async := false;
  IF v_result IS DISTINCT FROM -987654951 THEN
    RAISE EXCEPTION 'FEJL: OCR-låseorden fuldførte ikke citation-skriveren, resultat=%',v_result;
  END IF;
  PERFORM dblink_exec('ocr_lock_a','COMMIT');
  v_a_in_tx := false;

  v_deadline := clock_timestamp() + interval '10 seconds';
  LOOP
    SELECT dblink_is_busy('ocr_lock_b') INTO v_b_busy;
    EXIT WHEN v_b_busy = 0;
    IF clock_timestamp() > v_deadline THEN
      RAISE EXCEPTION 'FEJL: OCR-låseorden B overskred 10 sekunder';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  SELECT deleted INTO v_deleted FROM dblink_get_result('ocr_lock_b') AS t(deleted bigint);
  PERFORM * FROM dblink_get_result('ocr_lock_b') AS t(deleted bigint);
  v_b_async := false;
  IF v_deleted IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'FEJL: OCR-låseorden fuldførte ikke personsletningen, resultat=%',v_deleted;
  END IF;
  PERFORM dblink_exec('ocr_lock_b','COMMIT');
  v_b_in_tx := false;
  PERFORM dblink_disconnect('ocr_lock_a');
  PERFORM dblink_disconnect('ocr_lock_b');

  PERFORM dblink_exec('ocr_lock_setup',v_cleanup_sql);
  PERFORM dblink_disconnect('ocr_lock_setup');
  -- (2026-09-20) Vent AFGRAENSET paa at server-backends forsvinder, foer der maales.
  -- dblink_disconnect lukker klientsiden synkront, men backenden kan ligge et oejeblik
  -- i pg_stat_activity endnu. Et oejeblikkeligt tjek er derfor en race, ikke en
  -- logik-paastand — den faeldede bl.a. en REN dokumentations-merge paa main
  -- (bd68852, 2026-09-20), hvor intet SQL var aendret. Ventetiden er en oevre graense,
  -- ikke en forsinkelse: loekken forlades i samme oejeblik sessionerne er vaek.
  -- (2026-09-23) pg_stat_activity snapshottes ved foerste opslag og holdes resten af
  -- transaktionen; uden pg_stat_clear_snapshot() genlaeste loekken samme gamle billede i
  -- 5 s og faeldede CI (PR #215), naar backenden endnu levede ved foerste opslag.
  FOR i IN 1..50 LOOP
    PERFORM pg_stat_clear_snapshot();
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM pg_stat_activity
       WHERE datname=current_database() AND application_name LIKE 'daa_verify_ocr_lock_%');
    PERFORM pg_sleep(0.1);
  END LOOP;

  -- To adskilte paastande, ikke ét OR. Den gamle faellesbesked ("fixture ELLER
  -- dblink-session") kunne ikke fortaelle hvilken af to helt urelaterede aarsager der
  -- fyrede, og det er praecis derfor racen kunne overleve som "den der flaker nogle gange".
  IF EXISTS (
       SELECT 1 FROM source WHERE id=-987654601
       UNION ALL SELECT 1 FROM person WHERE id=-987654611
       UNION ALL SELECT 1 FROM person_external_id WHERE person_id=-987654611
       UNION ALL SELECT 1 FROM fact WHERE id=-987654701
       UNION ALL SELECT 1 FROM assertion WHERE id=-987654801
       UNION ALL SELECT 1 FROM conclusion WHERE id=-987654901
       UNION ALL SELECT 1 FROM citation WHERE id=-987654951
       UNION ALL SELECT 1 FROM import_korrektion
         WHERE import_key='verify:ocr:lock' AND record_key='I-lock'
       UNION ALL SELECT 1 FROM profiles WHERE id=v_uid
       UNION ALL SELECT 1 FROM auth.users WHERE id=v_uid
       UNION ALL SELECT 1 FROM change_set
         WHERE operation='red_slet_person' AND subjekt_type='person' AND subjekt_id=-987654611
     ) THEN
    RAISE EXCEPTION 'FEJL: OCR-låseorden efterlod fixture-rækker';
  END IF;
  IF EXISTS (
       SELECT 1 FROM pg_stat_activity
       WHERE datname=current_database() AND application_name LIKE 'daa_verify_ocr_lock_%'
     ) THEN
    RAISE EXCEPTION 'FEJL: OCR-låseorden efterlod en dblink-session efter 5 s: %',
      (SELECT string_agg(application_name||' ('||state||')', ', ')
         FROM pg_stat_activity
        WHERE datname=current_database() AND application_name LIKE 'daa_verify_ocr_lock_%');
  END IF;
  PERFORM set_config('daa.verify_dblink_ocr_lock','executed',false);
  RAISE NOTICE 'OK: OCR-låseorden to-forbindelsesregression';
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS
    v_error_state = RETURNED_SQLSTATE,
    v_error_message = MESSAGE_TEXT;

  -- Cancel/drain first when possible, explicitly roll back, and always disconnect.
  -- Disconnect is the final rollback guarantee if a remote query is still active.
  IF array_position(coalesce(dblink_get_connections(),'{}'::text[]),'ocr_lock_a') IS NOT NULL THEN
    BEGIN
      IF v_a_async AND dblink_is_busy('ocr_lock_a') = 1 THEN
        PERFORM dblink_cancel_query('ocr_lock_a');
      END IF;
      IF v_a_async THEN
        v_deadline := clock_timestamp() + interval '2 seconds';
        WHILE dblink_is_busy('ocr_lock_a') = 1 AND clock_timestamp() < v_deadline
          LOOP PERFORM pg_sleep(0.01); END LOOP;
        IF dblink_is_busy('ocr_lock_a') = 0 THEN
          PERFORM * FROM dblink_get_result('ocr_lock_a',false) AS t(id bigint);
          PERFORM * FROM dblink_get_result('ocr_lock_a',false) AS t(id bigint);
        END IF;
      END IF;
      IF v_a_in_tx THEN PERFORM dblink_exec('ocr_lock_a','ROLLBACK'); END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    BEGIN PERFORM dblink_disconnect('ocr_lock_a'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  IF array_position(coalesce(dblink_get_connections(),'{}'::text[]),'ocr_lock_b') IS NOT NULL THEN
    BEGIN
      IF v_b_async AND dblink_is_busy('ocr_lock_b') = 1 THEN
        PERFORM dblink_cancel_query('ocr_lock_b');
      END IF;
      IF v_b_async THEN
        v_deadline := clock_timestamp() + interval '2 seconds';
        WHILE dblink_is_busy('ocr_lock_b') = 1 AND clock_timestamp() < v_deadline
          LOOP PERFORM pg_sleep(0.01); END LOOP;
        IF dblink_is_busy('ocr_lock_b') = 0 THEN
          PERFORM * FROM dblink_get_result('ocr_lock_b',false) AS t(deleted bigint);
          PERFORM * FROM dblink_get_result('ocr_lock_b',false) AS t(deleted bigint);
        END IF;
      END IF;
      IF v_b_in_tx THEN PERFORM dblink_exec('ocr_lock_b','ROLLBACK'); END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    BEGIN PERFORM dblink_disconnect('ocr_lock_b'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  IF array_position(coalesce(dblink_get_connections(),'{}'::text[]),'ocr_lock_setup') IS NOT NULL THEN
    BEGIN PERFORM dblink_disconnect('ocr_lock_setup'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  -- Setup is autonomous/committed, so cleanup must be autonomous too. A fresh
  -- connection avoids an aborted setup/RPC transaction and retries success-cleanup errors.
  BEGIN
    IF array_position(coalesce(dblink_get_connections(),'{}'::text[]),'ocr_lock_cleanup') IS NOT NULL THEN
      PERFORM dblink_disconnect('ocr_lock_cleanup');
    END IF;
    PERFORM dblink_connect('ocr_lock_cleanup',
      v_conn || ' application_name=daa_verify_ocr_lock_cleanup');
    PERFORM dblink_exec('ocr_lock_cleanup',v_cleanup_sql);
    PERFORM dblink_disconnect('ocr_lock_cleanup');
  EXCEPTION WHEN OTHERS THEN
    v_cleanup_error := SQLERRM;
    BEGIN PERFORM dblink_disconnect('ocr_lock_cleanup'); EXCEPTION WHEN OTHERS THEN NULL; END;
    RAISE EXCEPTION USING
      ERRCODE = v_error_state,
      MESSAGE = format('%s; autonom cleanup fejlede: %s',v_error_message,v_cleanup_error);
  END;
  RAISE EXCEPTION USING ERRCODE = v_error_state, MESSAGE = v_error_message;
END $$;

-- ===== Person OCR kvalitetsark — samlet redaktionsprojektion =====
-- Selvstændig grid-fixture. Den ruller alle rækker tilbage og afprøver den faktiske
-- SECURITY DEFINER-overflade med lokale roller; den afhænger ikke af produktionsdata.
DO $$
DECLARE
  v_redaktor uuid := '00000000-0000-0000-0000-0000000000c3';
  v_anon_blokeret boolean := false;
  v_medlem_blokeret boolean := false;
  v_antal integer;
  v_qa text[];
BEGIN
  INSERT INTO source(id,titel,udgave,import_key) VALUES
    (-987656101,'Grid verify-kilde','Grid verify 1','verify:ocr-grid:1939'),
    (-987656102,'Grid verify-ekstra','Grid verify 2','verify:ocr-grid:1940');
  INSERT INTO person(id,koen) VALUES
    (-987656111,'mand'), (-987656112,'kvinde'), (-987656113,NULL),
    (-987656114,'ukendt'), (-987656115,'mand'), (-987656116,'kvinde');
  INSERT INTO person(id,koen) VALUES (-987656117,'mand');
  UPDATE person SET staged=true WHERE id=-987656114;
  INSERT INTO person_external_id(person_id,source_id,linje,nr,record_key,slaegtled_lokal) VALUES
    (-987656111,-987656101,'I',15,'I-15a',3),
    (-987656112,-987656101,'I',16,'I-16',3),
    (-987656113,-987656101,'I',17,NULL,4),
    (-987656114,-987656101,'II',1,'II-1',1),
    (-987656115,-987656101,'II',2,'II-2',1),
    (-987656116,-987656101,'II',3,'II-3',1),
    (-987656116,-987656102,'II',3,'II-3-ny',1),
    (-987656117,-987656101,'III',99,NULL,5);

  -- Normal person: selected source assertions, titel/familie/relation-counts and
  -- deliberately odd OCR/date context for the deterministic QA contract.
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES
    (-987656201,'person',-987656111,'navn'),
    (-987656202,'person',-987656111,'fødsel'),
    (-987656203,'person',-987656111,'død'),
    (-987656204,'person',-987656111,'titel'),
    (-987656205,'person',-987656112,'navn'),
    (-987656206,'person',-987656112,'fødsel'),
    (-987656207,'person',-987656112,'fødsel'),
    (-987656208,'person',-987656113,'fødsel'),
    (-987656209,'person',-987656114,'navn'),
    (-987656210,'person',-987656115,'navn'),
    (-987656211,'person',-987656116,'navn'),
    (-987656212,'person',-987656112,'død'),
    (-987656213,'person',-987656117,'navn'),
    (-987656214,'person',-987656117,'fødsel');
  INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,date_min,date_max,date_qualifier,date_raw)
  VALUES
    (-987656301,'fact',-987656201,'Mikkel',NULL,NULL,NULL,NULL),
    (-987656302,'fact',-987656202,NULL,'1901-01-01','1901-12-31','between','født 1901'),
    (-987656303,'fact',-987656203,NULL,'1900-01-01','1900-12-31','between','død 1900'),
    (-987656304,'fact',-987656204,'kammerherre',NULL,NULL,NULL,NULL),
    (-987656305,'fact',-987656205,'Ambig',NULL,NULL,NULL,NULL),
    (-987656306,'fact',-987656206,NULL,'1800-01-01','1800-12-31','between','født 1800'),
    (-987656307,'fact',-987656207,NULL,'1801-01-01','1801-12-31','between','født 1801'),
    (-987656308,'fact',-987656208,NULL,NULL,NULL,NULL,'dato kan ikke læses'),
    (-987656309,'fact',-987656209,'Uden kontekst',NULL,NULL,NULL,NULL),
    (-987656310,'fact',-987656210,'Alias',NULL,NULL,NULL,NULL),
    (-987656311,'fact',-987656211,'Kanonisk',NULL,NULL,NULL,NULL),
    (-987656312,'fact',-987656212,NULL,NULL,NULL,NULL,'dato kan ikke læses'),
    (-987656313,'fact',-987656213,'Legacy Navn Uden Anker',NULL,NULL,NULL,NULL),
    (-987656314,'fact',-987656214,NULL,'1690-01-01','1690-12-31','between','født 1690');
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status) VALUES
    (-987656401,'fact',-987656201,-987656301,'afklaret'),
    (-987656402,'fact',-987656202,-987656302,'afklaret'),
    (-987656403,'fact',-987656203,-987656303,'afklaret'),
    (-987656404,'fact',-987656204,-987656304,'afklaret'),
    (-987656405,'fact',-987656205,-987656305,'afklaret'),
    (-987656406,'fact',-987656206,-987656306,'afklaret'),
    (-987656407,'fact',-987656207,-987656307,'afklaret'),
    (-987656408,'fact',-987656208,-987656308,'afklaret'),
    (-987656409,'fact',-987656209,-987656309,'afklaret'),
    (-987656410,'fact',-987656210,-987656310,'forældet'),
    (-987656411,'fact',-987656211,-987656311,'afklaret'),
    (-987656412,'fact',-987656212,-987656312,'afklaret'),
    (-987656413,'fact',-987656213,-987656313,'afklaret'),
    (-987656414,'fact',-987656214,-987656314,'afklaret');
  INSERT INTO citation(id,assertion_id,source_id,side,citat_tekst) VALUES
    (-987656501,-987656301,-987656101,'42','Mikkel ?'),
    (-987656502,-987656302,-987656101,'42','født 1901'),
    (-987656503,-987656303,-987656101,'42','død 1900'),
    (-987656504,-987656304,-987656101,'42','kammerherre'),
    (-987656505,-987656305,-987656101,'43','Ambig'),
    (-987656506,-987656306,-987656101,'43','født 1800'),
    (-987656507,-987656307,-987656101,'43','født 1801'),
    (-987656508,-987656308,-987656101,'44','dato kan ikke læses'),
    (-987656510,-987656310,-987656101,'45','Alias'),
    (-987656511,-987656311,-987656101,'45','Kanonisk'),
    (-987656512,-987656312,-987656101,'44','dato kan ikke læses'),
    (-987656513,-987656313,-987656101,'99','Legacy Navn Uden Anker'),
    (-987656514,-987656314,-987656101,'99','født 1690');
  INSERT INTO import_korrektion(import_key,record_key,felt,input_fingerprint,importeret,korrigeret,status)
    VALUES ('verify:ocr-grid:1939','I-15a','navn','0123456789abcdef0123456789abcdef',
            '{"value":"Mikkel"}','{"value":"Mikkel rettet"}','rettet');
  INSERT INTO family(id,type) VALUES (-987656601,'vielse');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (-987656601,-987656111,'partner');
  INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES
    (-987656701,'person',-987656111,'person',-987656112,'bekendt_med'),
    (-987656702,'person',-987656115,'person',-987656116,'samme_som');

  -- samme_som-KÆDE: -987656119 er BÅDE alias (af -987656120) OG kanonisk (for
  -- -987656118). same_as_context producerede før én række pr. rolle, og da de to
  -- rækker adskiller sig på samme_som_status overlevede begge GROUP BY'et — samme
  -- fysiske person kom altså ud af griddet TO gange. Griddet lover én række pr.
  -- fysisk person; kæden låser det løfte fast.
  --
  -- RÆKKEFØLGEN ER IKKE VILKÅRLIG. enforce_samme_som_invariants() er BEFORE INSERT,
  -- og G4 tjekker kun om den NYE rækkes SUBJEKT allerede er kanonisk — ikke om dens
  -- OBJEKT allerede er alias. Indsættes den inderste kant (119→120) først, slipper
  -- den ydre (118→119) derfor igennem, og kæden opstår. Det er ikke et hul jeg
  -- opfinder til testen: præcis én person i prod står i den tilstand. Den omvendte
  -- rækkefølge ville blive afvist af G4 — griddet skal alligevel kunne tåle
  -- tilstanden, uanset om invarianten senere strammes.
  INSERT INTO person(id,koen) VALUES
    (-987656118,'mand'), (-987656119,'mand'), (-987656120,'mand');
  INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES
    (-987656704,'person',-987656119,'person',-987656120,'samme_som');
  INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES
    (-987656703,'person',-987656118,'person',-987656119,'samme_som');

  -- Fingerprint-parity with Task 2's independently fixed UTF-8 vector.
  IF ocr_input_fingerprint('daa:1939','I-15a','foedsel',
       '{"raw":"* 1644","min":"1644-01-01","max":"1644-12-31","qualifier":null,"calendar":"gregoriansk","certainty":null}'::jsonb,
       'side=42;span=1') <> '5fc3d843cc82550a45ff2a176bc7cc83' THEN
    RAISE EXCEPTION 'FEJL: OCR-fingerprint er ikke i Task 2-paritet';
  END IF;

  -- EXECUTE ACL plus SECURITY DEFINER-role guard are both part of the contract.
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM * FROM red_person_grid();
  EXCEPTION WHEN insufficient_privilege THEN v_anon_blokeret := true;
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub','',true);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM * FROM red_person_grid();
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'Kun redaktion%' THEN v_medlem_blokeret := true; ELSE RAISE; END IF;
  END;
  RESET ROLE;
  INSERT INTO auth.users(id,email) VALUES (v_redaktor,'ocr-grid-verify@test.invalid');
  INSERT INTO profiles(id,rolle,email) VALUES (v_redaktor,'redaktion','ocr-grid-verify@test.invalid');
  PERFORM set_config('request.jwt.claim.sub',v_redaktor::text,true);
  SET LOCAL ROLE authenticated;

  SELECT count(*) INTO v_antal FROM red_person_grid() WHERE person_id BETWEEN -987656116 AND -987656111;
  IF v_antal <> 6 THEN RAISE EXCEPTION 'FEJL: grid returnerede %/6 fysiske personer', v_antal; END IF;
  IF (SELECT count(*) FROM red_person_grid() WHERE person_id IN (-987656115,-987656116)) <> 2
     OR (SELECT kanonisk_person_id FROM red_person_grid() WHERE person_id=-987656115) <> -987656116 THEN
    RAISE EXCEPTION 'FEJL: grid kollapser eller mister samme_som-kontekst';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656111
                 AND antal_titler=1 AND antal_familier=1 AND antal_relationer=1
                 AND antal_kilde_assertions=4
                 AND ocr_context->>'navn'='Mikkel ?' AND kilde_side->>'navn'='42') THEN
    RAISE EXCEPTION 'FEJL: grid-counts eller valgt assertions OCR-kontekst er forkert';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656112
                 AND kan_rettes->>'foedsel'='false'
                 AND blokarsager->>'foedsel'='flere_importerede_facts'
                 AND foedsel_assertion_id IS NULL AND foedsel_raw IS NULL
                 AND foedsel_min IS NULL AND foedsel_max IS NULL
                 AND ocr_context->'foedsel' IS NULL) THEN
    RAISE EXCEPTION 'FEJL: flere importerede fødselsfacts er ikke koherent fail-closed';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656115
                 AND navn IS NULL AND navn_assertion_id IS NULL
                 AND kan_rettes->>'navn'='false'
                 AND NOT (qa_koder @> ARRAY['ocr_kontekst_mangler']::text[])) THEN
    RAISE EXCEPTION 'FEJL: ikke-afklaret konklusion projekteres stadig';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656116
                 AND kan_rettes='{"navn": false, "foedsel": false, "doed": false, "koen": false}'::jsonb
                 AND blokarsager='{"navn": "flere_importankre", "foedsel": "flere_importankre", "doed": "flere_importankre", "koen": "flere_importankre"}'::jsonb) THEN
    RAISE EXCEPTION 'FEJL: flere importankre er ikke blokeret for alle felter';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656113
                 AND kan_rettes->>'navn'='false' AND blokarsager->>'navn'='record_key_mangler') THEN
    RAISE EXCEPTION 'FEJL: legacy-række uden record_key er ikke blokeret';
  END IF;
  -- En legacy-række uden stabilt anker (record_key NULL) kan ikke rettes, men skal
  -- stadig kunne IDENTIFICERES og TIDSFÆSTES i griddet. Fallback bruger den allerede
  -- afklarede evidens (selected_assertions, FØR anker-gaten) — IKKE person.visning_*,
  -- som viste sig at ignorere conclusion.status og derfor kan lække en forældet værdi.
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656117
                 AND navn='Legacy Navn Uden Anker' AND kan_rettes->>'navn'='false'
                 AND foedsel_min='1690-01-01' AND foedsel_max='1690-12-31'
                 AND kan_rettes->>'foedsel'='false') THEN
    RAISE EXCEPTION 'FEJL: legacy-række uden stabilt anker viser ikke afklaret evidens som navn/fødsel';
  END IF;
  -- Beskyttelse mod status-læk: -987656115's eneste navn-konklusion er 'forældet'
  -- (ikke afklaret). Fallback må IKKE hente fra en ikke-afklaret konklusion, selvom
  -- den har et gyldigt valgt_assertion_id — det ville lade en tilbagetrukket værdi
  -- sive ind i visningen. Denne test dækkede allerede dette FØR fallback blev tilføjet;
  -- den skal fortsat holde bagefter.

  SELECT qa_koder INTO v_qa FROM red_person_grid() WHERE person_id=-987656111;
  IF NOT (v_qa @> ARRAY['mistænkeligt_ocr_tegn','foedt_efter_doed','struktureret_afviger_fra_ocr']::text[]) THEN
    RAISE EXCEPTION 'FEJL: normale OCR-/dato-QA-koder mangler: %', v_qa;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656111
                 AND review_status->>'navn'='stale'
                 AND qa_koder @> ARRAY['kilde_aendret']::text[]
                 AND importeret->'navn'='{"value":"Mikkel"}'::jsonb
                 AND korrigeret->'navn'='{"value":"Mikkel rettet"}'::jsonb) THEN
    RAISE EXCEPTION 'FEJL: stale journal-overlay bevarer ikke immutable importinput';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656112 AND qa_koder @> ARRAY['flere_importerede_facts']::text[])
     OR NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656113 AND qa_koder @> ARRAY['dato_ufortolkelig','record_key_mangler']::text[])
     OR NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656114 AND qa_koder @> ARRAY['ocr_kontekst_mangler']::text[]) THEN
    RAISE EXCEPTION 'FEJL: deterministiske grid-QA-koder mangler ambig=% legacy=% staged_context=%',
      EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656112 AND qa_koder @> ARRAY['flere_importerede_facts']::text[]),
      EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656113 AND qa_koder @> ARRAY['dato_ufortolkelig','record_key_mangler']::text[]),
      EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656114 AND qa_koder @> ARRAY['ocr_kontekst_mangler']::text[]);
  END IF;

  -- ---- navn_mangler betyder "der vises intet navn" — IKKE "navnet kan ikke rettes" ----
  -- Redigerbarhed udtrykkes af kan_rettes/blokarsager. Da QA-koden tidligere målte på
  -- de anker-gatede felter (candidate_count/felt_vaerdi), mens VISNINGEN falder tilbage
  -- til afklaret evidens, flagede den hver eneste ikke-redigerbare række — 1169 af 1757
  -- i prod, alle med et synligt navn, nul ægte. Samme fejlklasse som den tomme
  -- navnekolonne: gaten hørte til redigerbarheden, ikke til værdien.

  -- (a) Anker-løs, men navn opløst via fallback => navnet mangler IKKE.
  IF EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656117
             AND qa_koder @> ARRAY['navn_mangler']::text[]) THEN
    RAISE EXCEPTION 'FEJL: navn_mangler sat på række der viser et navn (anker-løs fallback)';
  END IF;

  -- (b) Navn kendt (afklaret konklusion) men uden citation => vises, altså ikke
  -- navn_mangler; manglen er kildedækning, og den udtrykkes af ocr_kontekst_mangler
  -- + blokårsagen ingen_kildebelagt_assertion.
  IF EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656114
             AND qa_koder @> ARRAY['navn_mangler']::text[]) THEN
    RAISE EXCEPTION 'FEJL: navn_mangler forveksler manglende kildedækning med manglende navn';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656114
                 AND navn='Uden kontekst'
                 AND kan_rettes->>'navn'='false'
                 AND blokarsager->>'navn'='ingen_kildebelagt_assertion') THEN
    RAISE EXCEPTION 'FEJL: ukildebelagt navn vises ikke, eller er ikke blokeret for rettelse';
  END IF;

  -- (c) Ægte tomt navn SKAL stadig flages. -987656115's eneste navn-konklusion er
  -- 'forældet', så selected_assertions giver intet — der er reelt intet navn at vise.
  -- Denne retning er værnet mod at fixet bare slukker for koden.
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656115
                 AND navn IS NULL AND qa_koder @> ARRAY['navn_mangler']::text[]) THEN
    RAISE EXCEPTION 'FEJL: ægte manglende navn flages ikke længere';
  END IF;

  -- ---- én række pr. fysisk person, også midt i en samme_som-kæde ----
  IF (SELECT count(*) FROM red_person_grid() WHERE person_id=-987656119) <> 1 THEN
    RAISE EXCEPTION 'FEJL: person midt i samme_som-kæde duplikeres i griddet (% rækker)',
      (SELECT count(*) FROM red_person_grid() WHERE person_id=-987656119);
  END IF;
  -- Alias-rollen vinder over kanonisk: at være alias er det stærkere udsagn om
  -- personens identitetsstatus, og redaktøren skal kunne se hvem hun peger på.
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656119
                 AND samme_som_status='alias' AND kanonisk_person_id=-987656120) THEN
    RAISE EXCEPTION 'FEJL: kæde-person viser ikke alias-rollen mod sin kanoniske';
  END IF;
  IF EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656115
             AND (qa_koder @> ARRAY['dato_ufortolkelig']::text[])) THEN
    RAISE EXCEPTION 'FEJL: manglende fødsel/død blev fejlagtigt OCR-fejl';
  END IF;
  RESET ROLE;
  IF NOT v_anon_blokeret OR NOT v_medlem_blokeret THEN
    RAISE EXCEPTION 'FEJL: grid EXECUTE/gate anon=% medlem=%',v_anon_blokeret,v_medlem_blokeret;
  END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN others THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: Person OCR kvalitetsark — set-baseret grid, QA, fingerprint og roller';
  ELSE RAISE; END IF;
END $$;


-- ===== Task 2: Cache-regenerering — regen_person_visning + trigger =====
-- Selvstændig syntetisk selected-name fixture: nulstil cache; kald regen; bekræft
-- den eksakte valgte assertion genskabes. Hele fixturen rulles tilbage.
-- Forvent: NOTICE "OK: visning_navn regenereret".
BEGIN;
DO $$
DECLARE
  tid CONSTANT bigint := -987656201;
  fid CONSTANT bigint := -987656202;
  aid CONSTANT bigint := -987656203;
  cid CONSTANT bigint := -987656204;
  expected_name CONSTANT text := 'Task 2 syntetisk navn';
BEGIN
  INSERT INTO person(id, levende, privat)
  VALUES (tid, false, false);
  INSERT INTO fact(id, subjekt_type, subjekt_id, faktatype)
  VALUES (fid, 'person', tid, 'navn');
  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst)
  VALUES (aid, 'fact', fid, expected_name);
  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status)
  VALUES (cid, 'fact', fid, aid, 'afklaret');

  UPDATE person SET visning_navn=NULL WHERE id=tid;
  PERFORM regen_person_visning(tid);
  IF (SELECT visning_navn FROM person WHERE id=tid) IS DISTINCT FROM expected_name THEN
    RAISE EXCEPTION 'regen genskabte ikke visning_navn';
  END IF;
  RAISE NOTICE 'OK: visning_navn regenereret';
END $$;
ROLLBACK;


-- ===== Task 3: current_rolle + red_upsert_fakta (fact-triplet, rolle-gated) =====
-- (a) Uden redaktion-rolle: forvent afvisning.
-- Forvent: NOTICE "OK: medlem afvist".
-- NOTE: auth.uid() er NULL i SQL Editor → rolle 'medlem' → RAISE forventes.
-- Happy-path (insert med redaktion-session) testes i Task 9 via app-laget.

DO $$ BEGIN
  BEGIN
    PERFORM red_upsert_fakta('person', (SELECT id FROM person LIMIT 1), 'navn', 'Testnavn');
    RAISE EXCEPTION 'Forventede rolle-afvisning';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'Kun redaktion%' THEN RAISE NOTICE 'OK: medlem afvist';
    ELSE RAISE; END IF;
  END;
END $$;


-- ===== Task 4: red_set_konklusion + red_edit_oplysning + red_slet_oplysning =====
-- Seed et fact med to assertions, slet den valgte, bekræft konklusion peger på tilbageværende.
-- Forvent: NOTICE "OK: konklusion re-pegede til a2".
--
-- Blokken seeder selv en ægte syntetisk JWT-subject + redaktion-profil og ruller
-- både rolle- og datatest-fixtures tilbage.
BEGIN;
DO $$
DECLARE
  actor CONSTANT uuid := '19390000-0000-4000-8000-000000000204';
  fid CONSTANT bigint := -987656211;
  a1 CONSTANT bigint := -987656212;
  a2 CONSTANT bigint := -987656213;
  cid CONSTANT bigint := -987656214;
  chosen bigint;
BEGIN
  INSERT INTO auth.users(id,email) VALUES (actor,'task4-db-verify@example.invalid');
  INSERT INTO profiles(id,rolle,email) VALUES (actor,'redaktion','task4-db-verify@example.invalid');
  PERFORM set_config('request.jwt.claim.sub', actor::text, true);

  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (fid,'person',-99,'test_slet');
  INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,uforanderlig) VALUES (a1,'fact',fid,'A',false);
  INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,uforanderlig) VALUES (a2,'fact',fid,'B',false);
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id) VALUES (cid,'fact',fid,a1);
  -- Slet den valgte (a1); forvent konklusion re-peger til a2.
  PERFORM red_slet_oplysning(a1);
  SELECT valgt_assertion_id INTO chosen FROM conclusion WHERE id=cid;
  IF chosen = a2 THEN RAISE NOTICE 'OK: konklusion re-pegede til a2';
  ELSE RAISE EXCEPTION 'Forventede a2, fik %', chosen; END IF;
END $$;
ROLLBACK;


-- ===== Task 5: Direkte person/narrativ/relation-RPC'er (rolle-gated) =====
-- Forvent: NOTICE "OK: koen-RPC gated".
-- NOTE: auth.uid() er NULL i SQL Editor → rolle 'medlem' → RAISE forventes.
-- Happy-path (faktisk koen-sætning) testes via app-laget med redaktion-session.

DO $$ BEGIN
  -- gating: medlem (auth.uid() NULL) afvises
  BEGIN PERFORM red_set_koen((SELECT id FROM person LIMIT 1),'mand');
    RAISE EXCEPTION 'Forventede afvisning';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'Kun redaktion%' THEN RAISE NOTICE 'OK: koen-RPC gated';
    ELSE RAISE; END IF;
  END;
END $$;


-- ===== Task 6: red_suggest — medlem-forslag til staging =====
-- Forvent: NOTICE "OK: anon afvist".
-- NOTE: auth.uid() er NULL i SQL Editor → red_suggest rejser 'Login kræves'.
-- Happy-path (forslag med authenticated session) testes via app-laget.

DO $$ BEGIN
  BEGIN PERFORM red_suggest('fakta','person',1,'navn','Test');
    RAISE EXCEPTION 'Forventede login-afvisning';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'Login kræves%' THEN RAISE NOTICE 'OK: anon afvist';
    ELSE RAISE; END IF;
  END;
END $$;


-- ===== Task 7: Authenticated read-RLS + RPC-grants =====
-- Forvent: auth_policies >= 11 (auth_read × 10 tabeller + self_read + own_read).

SELECT count(*) AS auth_policies FROM pg_policies
 WHERE schemaname='public' AND policyname IN ('auth_read','self_read','own_read');
-- Forvent auth_policies >= 11


-- ===== Samlet politik-røgtest =====
-- Bredere tælling: alle fire navngivne politik-typer der forventes af dette migrations-sæt.
-- Forventet antal: mange (>10). Tjekker at anon_read (fra det eksisterende db-rls.sql),
-- auth_read, self_read og own_read alle er oprettet.

SELECT count(*) FROM pg_policies
  WHERE schemaname='public'
    AND policyname IN ('anon_read','auth_read','self_read','own_read');
-- Forventet: >= 12 (anon_read: mindst 1 fra tidligere migrations + auth_read: 10 + self_read: 1 + own_read: 1)


-- ===== Task 8: media afbildet-gating (anon) =====
-- Forvent: NOTICE "OK: media-gating ...". Seeder negative-id testrækker og rydder selv op.
-- Kører faktisk som rolle 'anon' (SET LOCAL ROLE) for at RAMME RLS — SQL Editor er ellers
-- ejer/bypass. Hele blokken er ét DO = én transaktion; rejser den, rulles seed-rækkerne tilbage.
-- Verificerer fail-closed-reglen: afdød afbildet → synlig, levende afbildet → skjult,
-- objekt uden afbildet-person → synlig.
DO $$
DECLARE vis_dead int; vis_live int; vis_obj int;
        fakta_dead int; fakta_live int; fakta_live_auth int; gate_naegtet boolean;
        gate_auth_naegtet boolean; privat_auth_naegtet boolean;
BEGIN
  -- ryd evt. rester fra et afbrudt løb
  -- Disjunkte id-rum: person -901/-902, media -941/-942/-943. Med sammenfaldende id'er
  -- ville en forkert media-gren (fx person_offentlig(p_id)) give NOEJAGTIG samme resultat,
  -- og fixturen ville ikke bevise, at synligheden foelger medierelationen (Codex-fund 2026-09-20).
  DELETE FROM fact     WHERE id IN (-901,-902);
  DELETE FROM relation WHERE id IN (-901,-902);
  DELETE FROM media    WHERE id IN (-941,-942,-943);
  DELETE FROM person   WHERE id IN (-901,-902);

  INSERT INTO person(id, levende, privat) VALUES (-901, false, false), (-902, true, false);
  -- maa_publiceres=true + upload_status='klar' på alle: isolér afbildet-gatingen fra rettigheds-gatingen
  -- (rettigheder testes separat i Task 12).
  INSERT INTO media(id, slags, titel, maa_publiceres, upload_status) VALUES
    (-941,'foto','portræt-afdød',      true,'klar'),
    (-942,'foto','portræt-levende',    true,'klar'),
    (-943,'segl','objekt-uden-person', true,'klar');
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle) VALUES
    (-901,'person',-901,'media',-941,'afbildet'),
    (-902,'person',-902,'media',-942,'afbildet');
  -- Fakta PAA medierne. Hele pointen med disse to: medie-tilknyttet indhold gates af
  -- entitet_offentlig('media', ...), som foer 2026-09-20 kun saa paa RETTIGHEDER. Begge
  -- medier er rettighedsfrigivet, saa den gamle regel gjorde BEGGE faktarakker synlige —
  -- ogsaa den paa billedet af den LEVENDE person, hvis medie-raekke selv var skjult.
  INSERT INTO fact(id, subjekt_type, subjekt_id, faktatype) VALUES
    (-901,'media',-941,'fotograf'),
    (-902,'media',-942,'fotograf');

  SET LOCAL ROLE anon;
  SELECT count(*) INTO vis_dead FROM media WHERE id = -941;
  SELECT count(*) INTO vis_live FROM media WHERE id = -942;
  SELECT count(*) INTO vis_obj  FROM media WHERE id = -943;
  SELECT count(*) INTO fakta_dead FROM fact WHERE id = -901;
  SELECT count(*) INTO fakta_live FROM fact WHERE id = -902;
  -- Rettighedsgaten er lukket for anon (2026-09-20); den lovlige vej er entitet_offentlig.
  BEGIN
    PERFORM public.media_rettigheder_ok(-942);
    gate_naegtet := false;
  EXCEPTION WHEN insufficient_privilege THEN
    gate_naegtet := true;
  END;
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO fakta_live_auth FROM fact WHERE id = -902;
  -- Medlemstieren skal OGSAA have mistet de to direkte medie-orakler (Codex-fund 2026-09-20):
  -- medlems-politikkerne bruger media_synlig_anon, saa begge svarer mere end tieren selv ser.
  BEGIN
    PERFORM public.media_synlig_auth(-942);
    gate_auth_naegtet := false;
  EXCEPTION WHEN insufficient_privilege THEN
    gate_auth_naegtet := true;
  END;
  BEGIN
    PERFORM public.media_afbilder_privat(-942);
    privat_auth_naegtet := false;
  EXCEPTION WHEN insufficient_privilege THEN
    privat_auth_naegtet := true;
  END;
  RESET ROLE;

  IF vis_dead = 1 AND vis_live = 0 AND vis_obj = 1
     AND fakta_dead = 1 AND fakta_live = 0 AND fakta_live_auth = 0
     AND gate_naegtet AND gate_auth_naegtet AND privat_auth_naegtet THEN
    RAISE NOTICE 'OK: media-gating (afdød synlig, levende skjult, objekt synligt) + medie-tilknyttede fakta følger mediet + rettighedsgaten lukket';
  ELSE
    RAISE EXCEPTION 'media-gating FEJL: afdød=% (vent 1), levende=% (vent 0), objekt=% (vent 1) | fakta afdød=% (vent 1), fakta levende anon=% (vent 0) medlem=% (vent 0) | gates nægtet: anon=%, medlem synlig_auth=%, medlem afbilder_privat=% (vent t,t,t)',
      vis_dead, vis_live, vis_obj, fakta_dead, fakta_live, fakta_live_auth,
      gate_naegtet, gate_auth_naegtet, privat_auth_naegtet;
  END IF;

  DELETE FROM fact     WHERE id IN (-901,-902);
  DELETE FROM relation WHERE id IN (-901,-902);
  DELETE FROM media    WHERE id IN (-941,-942,-943);
  DELETE FROM person   WHERE id IN (-901,-902);
END $$;


-- ===== Task 8b: F-02 authenticated (medlem) fail-close på levende =====
-- Forvent: NOTICE "OK: authenticated fail-close ...". Seeder negative-id rækker, rydder selv op.
-- Kører som rolle 'authenticated' UDEN jwt-sub → auth.uid()=NULL → current_rolle() ≠ 'redaktion',
-- så redaktion_read-laget fyrer IKKE og auth_read styrer alene (medlem-tier).
-- Invariant #8 (CLAUDE.md §3): LEVENDE kræver samtykke — indtil samtykke/scope findes skal
-- medlem-tier fail-close til samme regel som anon (afdøde synlige, levende skjult). Codex-fund F-02.
-- Dækker BÅDE person-laget OG media-laget (media_synlig_auth tillod ellers fotos af levende).
DO $$
DECLARE vis_live int; vis_dead int; media_live int; media_dead int;
BEGIN
  DELETE FROM relation WHERE id IN (-950,-951);
  DELETE FROM media    WHERE id IN (-950,-951);
  DELETE FROM person   WHERE id IN (-950,-951);
  INSERT INTO person(id, levende, privat) VALUES (-950, true, false), (-951, false, false);
  -- media der afbilder hhv. den levende og den afdøde person (rettigheder=klar, så kun GDPR-gating måles)
  INSERT INTO media(id, slags, titel, maa_publiceres, upload_status) VALUES
    (-950,'foto','portræt-levende', true,'klar'), (-951,'foto','portræt-afdød', true,'klar');
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle) VALUES
    (-950,'person',-950,'media',-950,'afbildet'), (-951,'person',-951,'media',-951,'afbildet');

  PERFORM set_config('request.jwt.claim.sub','', true);  -- ingen bruger → ikke-redaktion
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO vis_live   FROM person WHERE id = -950;
  SELECT count(*) INTO vis_dead   FROM person WHERE id = -951;
  SELECT count(*) INTO media_live FROM media  WHERE id = -950;
  SELECT count(*) INTO media_dead FROM media  WHERE id = -951;
  RESET ROLE;

  IF vis_live = 0 AND vis_dead = 1 AND media_live = 0 AND media_dead = 1 THEN
    RAISE NOTICE 'OK: authenticated fail-close (levende person+foto skjult, afdød synlig)';
  ELSE
    RAISE EXCEPTION 'F-02 FEJL: authenticated person levende=%/afdød=% (vent 0/1), media levende=%/afdød=% (vent 0/1)',
      vis_live, vis_dead, media_live, media_dead;
  END IF;

  DELETE FROM relation WHERE id IN (-950,-951);
  DELETE FROM media    WHERE id IN (-950,-951);
  DELETE FROM person   WHERE id IN (-950,-951);
END $$;


-- ===== Task 8c: F-02c polymorf entitets-gating (family + ukendt type fail-close) =====
-- Forvent: NOTICE "OK: F-02c ...". Codex dual-review-fund: "<>'person'"-mønstret var fail-OPEN for
-- (1) family-mål (levende families vielse-fakta/noter synlige for anon+auth) og (2) ukendte/fejlstavede
-- typer. Nu erstattet af entitet_offentlig() (+ family_offentlig()). Tester BEGGE retninger:
-- læk-siden (family/unknown skjult) OG over-hiding-siden (public entitets-data STADIG synligt).
DO $$
DECLARE
  fo_dead boolean; fo_live boolean;
  eo_dead boolean; eo_live boolean; fo_anon_naegtet boolean;
  leak_fam_anon int; leak_fam_auth int; leak_note_auth int; leak_mis int; leak_assert int;
  ok_deadfam int; ok_estate int; ok_org_rel int; ok_narr int;
BEGIN
  DELETE FROM citation WHERE id=-981; DELETE FROM assertion WHERE id=-981;
  DELETE FROM note WHERE id IN (-980,-981); DELETE FROM narrative WHERE id=-980;
  DELETE FROM relation WHERE id IN (-980,-981); DELETE FROM fact WHERE id IN (-980,-981,-982,-983);
  DELETE FROM family_member WHERE family_id IN (-980,-981); DELETE FROM family WHERE id IN (-980,-981);
  DELETE FROM organisation WHERE id=-999; DELETE FROM estate WHERE id=-999;
  DELETE FROM person WHERE id IN (-980,-981);

  INSERT INTO person(id,levende,privat) VALUES(-980,false,false),(-981,true,false);
  INSERT INTO organisation(id,navn) VALUES(-999,'testorg');  INSERT INTO estate(id,navn) VALUES(-999,'testgods');
  INSERT INTO family(id,type) VALUES(-980,'ægteskab'),(-981,'ægteskab');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES(-980,-980,'partner'),(-981,-981,'partner');
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES
    (-980,'family',-980,'vielse'),(-981,'family',-981,'vielse'),
    (-982,'Person',-981,'fødsel'),(-983,'estate',-999,'opførelse');
  INSERT INTO assertion(id,target_type,target_id) VALUES(-981,'fact',-981);  -- evidens på levende-fam-fact
  INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES
    (-980,'person',-980,'organisation',-999,'medlem'),(-981,'person',-981,'organisation',-999,'medlem');
  INSERT INTO narrative(id,subjekt_type,subjekt_id,tekst) VALUES(-980,'person',-980,'død bio');
  INSERT INTO note(id,target_type,target_id) VALUES(-980,'family',-980),(-981,'family',-981);

  -- Gatens LOGIK efterproeves som ejer. family_offentlig er IKKE laengere kaldbar af
  -- anon (anon-haerdningen 2026-09-19): den svarede false praecis naar en familie rummer
  -- en skjult person og var dermed et eksistens-orakel for uindloggede.
  SELECT public.family_offentlig(-980), public.family_offentlig(-981) INTO fo_dead, fo_live;

  SET LOCAL ROLE anon;
  -- Anons FAKTISKE vej gaar gennem entitet_offentlig, som er SECURITY DEFINER og derfor
  -- kalder gaten som ejeren. Den skal give samme svar som gaten selv.
  SELECT public.entitet_offentlig('family',-980), public.entitet_offentlig('family',-981)
    INTO eo_dead, eo_live;
  -- ... og det DIREKTE kald skal vaere lukket. Denne paastand laaser haerdningen fast,
  -- saa et fremtidigt genudstedt grant bliver fanget her i stedet for i prod.
  BEGIN
    PERFORM public.family_offentlig(-980);
    fo_anon_naegtet := false;
  EXCEPTION WHEN insufficient_privilege THEN
    fo_anon_naegtet := true;
  END;
  SELECT count(*) INTO leak_fam_anon FROM fact WHERE id=-981;
  SELECT count(*) INTO ok_deadfam FROM fact WHERE id=-980;   SELECT count(*) INTO ok_estate FROM fact WHERE id=-983;
  SELECT count(*) INTO ok_org_rel FROM relation WHERE id=-980; SELECT count(*) INTO ok_narr FROM narrative WHERE id=-980;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub','',true); SET LOCAL ROLE authenticated;
  SELECT count(*) INTO leak_fam_auth FROM fact WHERE id=-981;  SELECT count(*) INTO leak_note_auth FROM note WHERE id=-981;
  SELECT count(*) INTO leak_mis FROM fact WHERE id=-982;       SELECT count(*) INTO leak_assert FROM assertion WHERE id=-981;
  RESET ROLE;

  IF fo_dead AND NOT fo_live
     AND eo_dead AND NOT eo_live AND fo_anon_naegtet
     AND leak_fam_anon=0 AND leak_fam_auth=0 AND leak_note_auth=0 AND leak_mis=0 AND leak_assert=0
     AND ok_deadfam=1 AND ok_estate=1 AND ok_org_rel=1 AND ok_narr=1 THEN
    RAISE NOTICE 'OK: F-02c — family/unknown+evidens fail-closed, anons vej gennem entitet_offentlig intakt, direkte gate-kald lukket';
  ELSE
    RAISE EXCEPTION 'F-02c FEJL: gate død/lev=%/% | anon-vej død/lev=%/% | direkte gate-kald nægtet=% | læk fam(a/au)=%/% note=% mis=% assert=% | over-hide dødfam=% estate=% rel=% narr=%',
      fo_dead,fo_live,eo_dead,eo_live,fo_anon_naegtet,leak_fam_anon,leak_fam_auth,leak_note_auth,leak_mis,leak_assert,ok_deadfam,ok_estate,ok_org_rel,ok_narr;
  END IF;

  DELETE FROM citation WHERE id=-981; DELETE FROM assertion WHERE id=-981;
  DELETE FROM note WHERE id IN (-980,-981); DELETE FROM narrative WHERE id=-980;
  DELETE FROM relation WHERE id IN (-980,-981); DELETE FROM fact WHERE id IN (-980,-981,-982,-983);
  DELETE FROM family_member WHERE family_id IN (-980,-981); DELETE FROM family WHERE id IN (-980,-981);
  DELETE FROM organisation WHERE id=-999; DELETE FROM estate WHERE id=-999;
  DELETE FROM person WHERE id IN (-980,-981);
END $$;


-- ===== Task 9: lineage trin (b) — forgrening + status =====
-- Forvent: kolonnerne findes, og en selv-refererende gren (parent_lineage_id) + en
-- 'gren_af'-relation kan oprettes og resolveres. Seeder negative-id rækker, rydder op.
SELECT
  (SELECT count(*) FROM information_schema.columns
    WHERE table_schema='public' AND table_name='lineage' AND column_name='parent_lineage_id') AS har_parent,
  (SELECT count(*) FROM information_schema.columns
    WHERE table_schema='public' AND table_name='lineage' AND column_name='status') AS har_status;
-- Forvent har_parent=1, har_status=1

DO $$
DECLARE resolved_navn text; rel_ok int;
BEGIN
  DELETE FROM relation WHERE id = -910;
  DELETE FROM lineage  WHERE id IN (-910,-911);

  -- moderlinje + adlet gren der udgår af den
  INSERT INTO lineage(id, navn, status) VALUES (-910,'Test-moderlinje', NULL);
  INSERT INTO lineage(id, navn, parent_lineage_id, status)
    VALUES (-911,'Test-gren (adlet)', -910, 'uddød');
  -- evidens-bærende 'gren_af'-relation (polymorf, ingen skema-ændring)
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle, konfidens)
    VALUES (-910,'lineage',-911,'lineage',-910,'gren_af','sandsynlig');

  -- FK resolves: grenens parent peger på moderlinjens navn
  SELECT m.navn INTO resolved_navn
    FROM lineage g JOIN lineage m ON m.id = g.parent_lineage_id WHERE g.id = -911;
  SELECT count(*) INTO rel_ok FROM relation
    WHERE id=-910 AND rolle='gren_af' AND subjekt_type='lineage' AND objekt_type='lineage';

  IF resolved_navn = 'Test-moderlinje' AND rel_ok = 1 THEN
    RAISE NOTICE 'OK: lineage (b) — forgrening + gren_af-relation';
  ELSE
    RAISE EXCEPTION 'lineage (b) FEJL: parent_navn=% (vent Test-moderlinje), rel_ok=% (vent 1)',
      resolved_navn, rel_ok;
  END IF;

  DELETE FROM relation WHERE id = -910;
  DELETE FROM lineage  WHERE id IN (-910,-911);
END $$;


-- =====================================================================
--  VERSIONERING + HYPERLINKS (2026-06-30) — asserts pr. task
--  Køres mod KOPI/branch-base, aldrig prod (jf. plan Global Constraints).
-- =====================================================================

-- ===== Versionering Task 1: PK-registry =====
DO $$
BEGIN
  IF to_regclass('public.version_pk_registry') IS NULL THEN
    RAISE EXCEPTION 'FEJL: version_pk_registry mangler';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM version_pk_registry WHERE tabel='family_member'
                 AND pk_cols = ARRAY['family_id','person_id','rolle']) THEN
    RAISE EXCEPTION 'FEJL: family_member composite PK ikke registreret korrekt';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM version_pk_registry WHERE tabel='person'
                 AND skip_cols @> ARRAY['visning_navn','visning_foedt','visning_doed','visning_titel',
                                         'visning_efternavn','visning_fuldt_navn']) THEN
    RAISE EXCEPTION 'FEJL: person visning_* (inkl. udledt-slægtsnavn-kolonnerne) ikke i skip_cols';
  END IF;
  RAISE NOTICE 'OK: version_pk_registry seeded';
END $$;

-- ===== Versionering Task 2: change_set/change_event =====
DO $$
BEGIN
  IF to_regclass('public.change_set') IS NULL OR to_regclass('public.change_event') IS NULL THEN
    RAISE EXCEPTION 'FEJL: change_set/change_event mangler';
  END IF;
  -- actor_id skal være ON DELETE SET NULL (spec-B3/H6)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.referential_constraints rc
    JOIN information_schema.key_column_usage k ON k.constraint_name=rc.constraint_name
    WHERE k.table_name='change_set' AND k.column_name='actor_id' AND rc.delete_rule='SET NULL') THEN
    RAISE EXCEPTION 'FEJL: change_set.actor_id mangler ON DELETE SET NULL';
  END IF;
  RAISE NOTICE 'OK: change_set/change_event findes m. korrekt actor-FK';
END $$;

-- ===== Versionering Task 3: begin_change_set re-entrant =====
DO $$
DECLARE a bigint; b bigint;
BEGIN
  PERFORM set_config('app.change_set_id', '', true);  -- nulstil
  a := begin_change_set('test_op','sum','person',1);
  b := begin_change_set('indre_op','sum2','person',1); -- nested → skal genbruge a
  IF a <> b THEN RAISE EXCEPTION 'FEJL: nested begin_change_set gav nyt id (% <> %)', a, b; END IF;
  IF current_setting('app.change_set_id', true) <> a::text THEN
    RAISE EXCEPTION 'FEJL: session-variabel ikke sat'; END IF;
  DELETE FROM change_set WHERE id=a;  -- oprydning
  PERFORM set_config('app.change_set_id', '', true);
  RAISE NOTICE 'OK: begin_change_set er re-entrant';
END $$;

-- ===== Versionering Task 4: log_change trigger =====
DO $$
DECLARE cs bigint; n int; ev change_event;
BEGIN
  -- (a) UDEN aktivt change_set: en UPDATE logges IKKE (bulk-load-sti)
  PERFORM set_config('app.change_set_id','',true);
  UPDATE person SET status=status WHERE id=(SELECT id FROM person LIMIT 1);
  -- (b) MED aktivt change_set: en ægte ændring logges
  cs := begin_change_set('test_log','t','person',NULL);
  UPDATE person SET status='__verify__' WHERE id=(SELECT id FROM person LIMIT 1);
  SELECT count(*) INTO n FROM change_event WHERE change_set_id=cs AND tabel='person';
  IF n <> 1 THEN RAISE EXCEPTION 'FEJL: forventede 1 person-event, fik %', n; END IF;
  -- (c) visning_* ekskluderet fra snapshot
  SELECT * INTO ev FROM change_event WHERE change_set_id=cs AND tabel='person' LIMIT 1;
  IF ev.efter ? 'visning_navn' THEN RAISE EXCEPTION 'FEJL: visning_navn ikke ekskluderet'; END IF;
  -- (d) kun-visning-ændring logges IKKE
  UPDATE person SET visning_navn='__x__' WHERE id=(ev.row_pk->>'id')::bigint;
  IF (SELECT count(*) FROM change_event WHERE change_set_id=cs AND tabel='person') <> 1 THEN
    RAISE EXCEPTION 'FEJL: kun-cache-ændring blev logget'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';  -- rul alt tilbage (vi muterede rigtige rækker)
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: log_change logger korrekt (rullet tilbage)';
    ELSE RAISE; END IF;
END $$;

-- ===== Versionering Task 5: RPC-wiring =====
DO $$
DECLARE r jsonb; cs bigint; n int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  r := red_opret_fakta('person',(SELECT id FROM person LIMIT 1),'tilnavn','__verify__',NULL,NULL,NULL,NULL,'testkilde');
  -- find seneste change_set og tæl events (fact+assertion+citation+conclusion = 4)
  SELECT max(id) INTO cs FROM change_set;
  SELECT count(*) INTO n FROM change_event WHERE change_set_id=cs;
  IF n < 4 THEN RAISE EXCEPTION 'FEJL: red_opret_fakta grupperede ikke 4 rækker (fik %)', n; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: RPC grupperer rækker i ét change_set';
  ELSE RAISE; END IF;
END $$;

-- ===== Versionering Task 5b: re-entrant nested wiring (red_opret_person → red_upsert_fakta) =====
-- Dækker flerlinjet-rolle-tjek-stien (red_upsert_fakta) som 5a ikke rører, og B7-re-entrancy:
-- nested red_* må IKKE åbne et nyt change_set.
DO $$
DECLARE r jsonb; v_pid bigint; cs_before bigint; cs_after bigint; n_sets int; n_person int; n_fact int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  cs_before := (SELECT coalesce(max(id),0) FROM change_set);
  v_pid := red_opret_person('__verify_person__','mand',false,'1700','1750',NULL);
  cs_after := (SELECT coalesce(max(id),0) FROM change_set);
  -- præcis ÉT nyt change_set (re-entrancy: nested red_upsert_fakta åbnede ikke flere)
  SELECT count(*) INTO n_sets FROM change_set WHERE id > cs_before;
  IF n_sets <> 1 THEN RAISE EXCEPTION 'FEJL: red_opret_person åbnede % change_sets (vent 1)', n_sets; END IF;
  -- person-INSERT logget i sættet (beviser ydre begin_change_set kørte FØR person-INSERT)
  SELECT count(*) INTO n_person FROM change_event WHERE change_set_id=cs_after AND tabel='person' AND op='INSERT';
  IF n_person <> 1 THEN RAISE EXCEPTION 'FEJL: person-INSERT ikke logget (fik %)', n_person; END IF;
  -- nested red_upsert_fakta logget i SAMME sæt (beviser red_upsert_fakta-wiring kører for redaktion)
  SELECT count(*) INTO n_fact FROM change_event WHERE change_set_id=cs_after AND tabel='fact' AND op='INSERT';
  IF n_fact < 1 THEN RAISE EXCEPTION 'FEJL: nested fakta ikke logget i samme sæt (fik %)', n_fact; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: nested red_opret_person re-entrant (ét sæt, person+fakta logget)';
  ELSE RAISE; END IF;
END $$;

-- ===== Versionering Task 6: red_edit_oplysning append =====
DO $$
DECLARE v_fact bigint; v_old bigint; v_concl_valgt bigint; n_before int; n_after int; r jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  r := red_opret_fakta('person',(SELECT id FROM person LIMIT 1),'tilnavn','gammel',NULL,NULL,NULL,NULL,'k');
  v_old := (r->>'assertion_id')::bigint; v_fact := (r->>'fact_id')::bigint;
  SELECT count(*) INTO n_before FROM assertion WHERE target_type='fact' AND target_id=v_fact;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_edit_oplysning(v_old, 'rettet', NULL, NULL);
  SELECT count(*) INTO n_after FROM assertion WHERE target_type='fact' AND target_id=v_fact;
  IF n_after <> n_before + 1 THEN RAISE EXCEPTION 'FEJL: edit oprettede ikke ny assertion (% -> %)', n_before, n_after; END IF;
  IF NOT EXISTS (SELECT 1 FROM assertion WHERE id=v_old AND vaerdi_tekst='gammel') THEN
    RAISE EXCEPTION 'FEJL: gammel assertion blev muteret/slettet'; END IF;
  SELECT valgt_assertion_id INTO v_concl_valgt FROM conclusion WHERE target_type='fact' AND target_id=v_fact;
  IF (SELECT vaerdi_tekst FROM assertion WHERE id=v_concl_valgt) <> 'rettet' THEN
    RAISE EXCEPTION 'FEJL: konklusion peger ikke på ny værdi'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: red_edit_oplysning er append';
  ELSE RAISE; END IF;
END $$;

-- ===== Versionering Task 7: restore-hjælpere =====
DO $$
DECLARE v_id bigint; cur jsonb;
BEGIN
  v_id := (SELECT coalesce(max(id),0)+1 FROM note);
  PERFORM _version_upsert_row('note', jsonb_build_object('id',v_id,'target_type','person','target_id',1,'indhold','A','privat',false));
  cur := _version_current_row('note', jsonb_build_object('id',v_id));
  IF cur->>'indhold' <> 'A' THEN RAISE EXCEPTION 'FEJL: upsert insert virkede ikke'; END IF;
  PERFORM _version_upsert_row('note', jsonb_build_object('id',v_id,'target_type','person','target_id',1,'indhold','B','privat',false));
  cur := _version_current_row('note', jsonb_build_object('id',v_id));
  IF cur->>'indhold' <> 'B' THEN RAISE EXCEPTION 'FEJL: upsert update virkede ikke'; END IF;
  PERFORM _version_delete_row('note', jsonb_build_object('id',v_id));
  IF _version_current_row('note', jsonb_build_object('id',v_id)) IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: delete virkede ikke'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: restore-hjælpere round-trip';
  ELSE RAISE; END IF;
END $$;

-- ===== Versionering Task 8: restore =====
DO $$
DECLARE r jsonb; v_fact bigint; v_aid bigint; cs bigint; v_val text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  -- opret en oplysning (change_set #1)
  PERFORM set_config('app.change_set_id','',true);
  r := red_opret_fakta('person',(SELECT id FROM person LIMIT 1),'tilnavn','original',NULL,NULL,NULL,NULL,'k');
  v_aid := (r->>'assertion_id')::bigint; v_fact := (r->>'fact_id')::bigint;
  SELECT max(id) INTO cs FROM change_set;
  -- fortryd #1 → fact/assertion/citation/conclusion skal forsvinde igen
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(cs, false);
  IF EXISTS (SELECT 1 FROM assertion WHERE id=v_aid) THEN
    RAISE EXCEPTION 'FEJL: restore slettede ikke den oprettede assertion'; END IF;
  IF NOT EXISTS (SELECT 1 FROM change_set WHERE reverterer_id=cs) THEN
    RAISE EXCEPTION 'FEJL: ingen reversal-change_set oprettet'; END IF;
  -- dobbelt-fortryd af samme sæt skal afvises
  BEGIN
    PERFORM red_fortryd_change_set(cs, false);
    RAISE EXCEPTION 'FEJL: dobbelt-fortryd blev ikke afvist';
  EXCEPTION WHEN OTHERS THEN
    -- forventet: funktionen afviser med "... er allerede fortrudt" → svælg.
    -- Re-raise KUN hvis afvisningen udeblev (vores egen "blev ikke afvist"-fejl).
    IF SQLERRM LIKE '%blev ikke afvist%' THEN RAISE;
    END IF;
  END;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: restore round-trip + dobbelt-fortryd afvist';
  ELSE RAISE; END IF;
END $$;

-- ===== Versionering Task 8b: person-slet-restore (FK-graf, H5) =====
-- Dækker H5: red_slet_person sletter børn før forælder → omvendt-seq genindsætter
-- forælder før børn (FK-sikkert). Fakta-stien (8a) rører ikke denne ordning.
DO $$
DECLARE v_pid bigint; cs_del bigint; n_facts_before int; n_facts_after int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  v_pid := red_opret_person('__verify_slet__','kvinde',false,'1600','1660','Fru');
  SELECT count(*) INTO n_facts_before FROM fact WHERE subjekt_type='person' AND subjekt_id=v_pid;
  -- slet personen (eget change_set)
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_slet_person(v_pid);
  SELECT max(id) INTO cs_del FROM change_set;
  IF EXISTS (SELECT 1 FROM person WHERE id=v_pid) THEN RAISE EXCEPTION 'FEJL: person ikke slettet'; END IF;
  -- fortryd sletningen → person + alle børn (fact/assertion/citation/conclusion) tilbage
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(cs_del, false);
  IF NOT EXISTS (SELECT 1 FROM person WHERE id=v_pid) THEN
    RAISE EXCEPTION 'FEJL: person ikke genskabt ved restore'; END IF;
  SELECT count(*) INTO n_facts_after FROM fact WHERE subjekt_type='person' AND subjekt_id=v_pid;
  IF n_facts_after <> n_facts_before THEN
    RAISE EXCEPTION 'FEJL: fakta ikke fuldt genskabt (% -> %)', n_facts_before, n_facts_after; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: person-slet-restore genskaber fuld FK-graf';
  ELSE RAISE; END IF;
END $$;

-- ===== Hyperlinks Task 9: parse_mentions =====
DO $$
DECLARE n int; got record;
BEGIN
  -- gyldigt token + malformet + ukendt type + escaped pipe i visningstekst
  SELECT count(*) INTO n FROM parse_mentions(
    'Se [[person:482|Chr. D. Reventlow]] og [[estate:7|Christianssæde]]. '
    || 'Malformet [[person:abc|x]] ukendt [[ufo:1|y]] escaped [[person:9|a\|b]].');
  IF n <> 3 THEN RAISE EXCEPTION 'FEJL: forventede 3 gyldige mentions, fik %', n; END IF;
  IF NOT EXISTS (SELECT 1 FROM parse_mentions('[[person:482|x]]') WHERE maal_type='person' AND maal_id=482) THEN
    RAISE EXCEPTION 'FEJL: token ikke parset korrekt'; END IF;
  RAISE NOTICE 'OK: parse_mentions';
END $$;

-- ===== Hyperlinks Task 10: text_mention =====
DO $$
DECLARE v_nid bigint; n int;
BEGIN
  PERFORM set_config('app.change_set_id','',true);  -- bulk-sti, ingen versionering af testdata
  v_nid := (SELECT coalesce(max(id),0)+1 FROM narrative);
  INSERT INTO narrative(id,subjekt_type,subjekt_id,tekst)
    VALUES (v_nid,'person',1,'[[person:1|a]] og [[person:1|igen]] og [[estate:2|g]]');
  SELECT count(*) INTO n FROM text_mention WHERE kilde_type='narrative' AND kilde_id=v_nid;
  IF n <> 2 THEN RAISE EXCEPTION 'FEJL: forventede 2 dedup-mentions, fik %', n; END IF;  -- person:1 dedup
  UPDATE narrative SET tekst='[[lineage:5|x]]' WHERE id=v_nid;  -- replace
  SELECT count(*) INTO n FROM text_mention WHERE kilde_type='narrative' AND kilde_id=v_nid;
  IF n <> 1 OR NOT EXISTS (SELECT 1 FROM text_mention WHERE kilde_id=v_nid AND maal_type='lineage') THEN
    RAISE EXCEPTION 'FEJL: replace-semantik virkede ikke'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: text_mention dedup + replace';
  ELSE RAISE; END IF;
END $$;

-- ===== Task 11: historik-RLS + døde links =====
DO $$
DECLARE n int;
BEGIN
  IF to_regclass('public.red_doede_links') IS NULL THEN
    RAISE EXCEPTION 'FEJL: red_doede_links view mangler'; END IF;
  -- hist_for_subjekt skal RAISE for ikke-redaktion (SQL Editor = medlem)
  BEGIN
    PERFORM * FROM hist_for_subjekt('person', 1);
    RAISE EXCEPTION 'FEJL: hist_for_subjekt tillod ikke-redaktion';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'FEJL:%' THEN RAISE; END IF;  -- vores assert-fejl propagerer
  END;
  -- hist_for_subjekter skal RAISE for ikke-redaktion (SQL Editor = medlem)
  BEGIN
    PERFORM * FROM hist_for_subjekter('person', ARRAY[1]::bigint[]);
    RAISE EXCEPTION 'FEJL: hist_for_subjekter tillod ikke-redaktion';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'FEJL:%' THEN RAISE; END IF;  -- vores assert-fejl propagerer
  END;
  RAISE NOTICE 'OK: historik-API redaktion-gated + døde-links-view findes';
END $$;

-- ===== Fase 4.1: batchet tværudgave-match-RPC =====
DO $$
DECLARE
  v_uid uuid := gen_random_uuid();
  v_result jsonb;
  v_denied boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM red_match_personer();
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'Kun redaktion%' THEN v_denied := true;
    ELSE RAISE; END IF;
  END;
  RESET ROLE;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'FEJL: red_match_personer tillod ikke-redaktion';
  END IF;

  INSERT INTO auth.users(id,email) VALUES (v_uid,'match-rpc-verify@test.invalid');
  INSERT INTO profiles(id,rolle,email) VALUES (v_uid,'redaktion','match-rpc-verify@test.invalid');
  PERFORM set_config('request.jwt.claim.sub',v_uid::text,true);
  SET LOCAL ROLE authenticated;
  v_result := red_match_personer();
  RESET ROLE;

  IF v_result IS NULL
     OR NOT v_result ?& ARRAY['persons','facts','concs','assertions','extIds']
     OR jsonb_typeof(v_result->'persons') <> 'array'
     OR jsonb_array_length(v_result->'persons') <> (SELECT count(*) FROM person) THEN
    RAISE EXCEPTION 'FEJL: red_match_personer returnerede ugyldigt datasæt';
  END IF;

  DELETE FROM profiles WHERE id=v_uid;
  DELETE FROM auth.users WHERE id=v_uid;
  PERFORM set_config('request.jwt.claim.sub','',true);
  RAISE NOTICE 'OK: red_match_personer er redaktion-gated og returnerer komplet rådatasæt';
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  DELETE FROM profiles WHERE id=v_uid;
  DELETE FROM auth.users WHERE id=v_uid;
  PERFORM set_config('request.jwt.claim.sub','',true);
  RAISE;
END $$;

-- ===== Mediehåndtering fase 2: døde media-mentions =====
-- Token-id'er skal være positive: parse_mentions-kontrakten accepterer ikke negative id'er.
DO $$
DECLARE
  v_nid bigint := -999903;
  v_manglende_media_id bigint := 999999901;
  v_eksisterende_media_id bigint := 999999902;
BEGIN
  PERFORM set_config('app.change_set_id','',true);  -- bulk-sti, ingen versionering af testdata

  IF NOT EXISTS (
    SELECT 1 FROM pg_class
    WHERE oid='public.red_doede_links'::regclass
      AND coalesce(reloptions, ARRAY[]::text[]) @> ARRAY['security_invoker=true']
  ) THEN
    RAISE EXCEPTION 'FEJL: red_doede_links har mistet security_invoker=true';
  END IF;

  INSERT INTO media(id, slags, titel, upload_status)
    VALUES (v_eksisterende_media_id, 'foto', '__verify_doede_links__', 'klar');
  INSERT INTO narrative(id, subjekt_type, subjekt_id, tekst)
    VALUES (
      v_nid,
      'person',
      1,
      format(
        '[[media:%s|mangler]] og [[media:%s|findes]]',
        v_manglende_media_id,
        v_eksisterende_media_id
      )
    );

  IF NOT EXISTS (
    SELECT 1 FROM text_mention
    WHERE kilde_type='narrative' AND kilde_id=v_nid
      AND maal_type='media' AND maal_id=v_manglende_media_id
  ) OR NOT EXISTS (
    SELECT 1 FROM text_mention
    WHERE kilde_type='narrative' AND kilde_id=v_nid
      AND maal_type='media' AND maal_id=v_eksisterende_media_id
  ) THEN
    RAISE EXCEPTION 'FEJL: mention-triggeren indekserede ikke begge media-tokens';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM red_doede_links
    WHERE kilde_type='narrative' AND kilde_id=v_nid
      AND maal_type='media' AND maal_id=v_manglende_media_id
  ) THEN
    RAISE EXCEPTION 'FEJL: manglende media blev ikke vist som dødt link';
  END IF;
  IF EXISTS (
    SELECT 1 FROM red_doede_links
    WHERE kilde_type='narrative' AND kilde_id=v_nid
      AND maal_type='media' AND maal_id=v_eksisterende_media_id
  ) THEN
    RAISE EXCEPTION 'FEJL: eksisterende media blev fejlagtigt vist som dødt link';
  END IF;

  UPDATE media SET upload_status='fjernet' WHERE id=v_eksisterende_media_id;
  IF EXISTS (
    SELECT 1 FROM red_doede_links
    WHERE kilde_type='narrative' AND kilde_id=v_nid
      AND maal_type='media' AND maal_id=v_eksisterende_media_id
  ) THEN
    RAISE EXCEPTION 'FEJL: fjernet media blev fejlagtigt vist som dødt link';
  END IF;

  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: døde media-mentions skelner manglende/fjernet (rullet tilbage)';
  ELSE RAISE; END IF;
END $$;

-- ===== Mediehåndtering fase 2: redaktionen ser private media-mentions =====
DO $$
DECLARE
  v_uid uuid := '00000000-0000-0000-0000-00000000f202';
  v_member_uid uuid := '00000000-0000-0000-0000-00000000f203';
  v_nid bigint := -999904;
  v_public_nid bigint := -999905;
  v_public_person_id bigint := 999999905;
  v_media_id bigint := 999999904;
  v_hidden_media_id bigint := 999999906;
  v_missing_media_id bigint := 999999907;
  v_anon int;
  v_member int;
  v_redaktion int;
  v_dead_redaktion int;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='text_mention'
      AND policyname='redaktion_read'
      AND roles @> ARRAY['authenticated']::name[]
  ) THEN
    RAISE EXCEPTION 'FEJL: text_mention.redaktion_read-policy mangler';
  END IF;

  -- Lokale PostgreSQL-shims har ikke Supabases default grants. De midlertidige
  -- grants rulles tilbage sammen med fixtures og tester kun policy-adfærden.
  EXECUTE 'GRANT SELECT ON text_mention, red_doede_links TO anon, authenticated';
  INSERT INTO auth.users(id,email) VALUES
    (v_uid,'media-fase2@test.invalid'),
    (v_member_uid,'media-fase2-member@test.invalid');
  INSERT INTO profiles(id,rolle,email) VALUES
    (v_uid,'redaktion','media-fase2@test.invalid'),
    (v_member_uid,'medlem','media-fase2-member@test.invalid');
  INSERT INTO person(id,levende,privat) VALUES (v_public_person_id,false,false);
  INSERT INTO media(id,slags,titel,upload_status,maa_publiceres) VALUES
    (v_media_id,'foto','__verify_public_media__','klar',true),
    (v_hidden_media_id,'foto','__verify_hidden_media__','fjernet',true);
  INSERT INTO narrative(id,subjekt_type,subjekt_id,tekst,privat)
    VALUES
      (v_nid,'person',-999904,format('[[media:%s|privat]]',v_media_id),true),
      (v_public_nid,'person',v_public_person_id,
        format('[[media:%s|klar]] [[media:%s|skjult]] [[media:%s|mangler]]',
          v_media_id,v_hidden_media_id,v_missing_media_id),false);

  IF NOT EXISTS (
    SELECT 1 FROM text_mention
    WHERE kilde_type='narrative' AND kilde_id=v_nid
      AND maal_type='media' AND maal_id=v_media_id
  ) THEN
    RAISE EXCEPTION 'FEJL: privat media-token blev ikke indekseret';
  END IF;

  PERFORM set_config('request.jwt.claim.sub','',true);
  SET LOCAL ROLE anon;
  SELECT count(*) INTO v_anon FROM text_mention
    WHERE kilde_type='narrative' AND kilde_id IN (v_nid,v_public_nid)
      AND maal_type='media';
  RESET ROLE;

  PERFORM set_config('request.jwt.claim.sub',v_member_uid::text,true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_member FROM text_mention
    WHERE kilde_type='narrative' AND kilde_id IN (v_nid,v_public_nid)
      AND maal_type='media';
  RESET ROLE;

  PERFORM set_config('request.jwt.claim.sub',v_uid::text,true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_redaktion FROM text_mention
    WHERE kilde_type='narrative' AND kilde_id IN (v_nid,v_public_nid)
      AND maal_type='media';
  SELECT count(*) INTO v_dead_redaktion FROM red_doede_links
    WHERE kilde_type='narrative' AND kilde_id=v_public_nid AND maal_type='media';
  RESET ROLE;

  IF v_anon <> 1 OR v_member <> 1 OR v_redaktion <> 4 OR v_dead_redaktion <> 1 THEN
    RAISE EXCEPTION 'FEJL: media-mention RLS anon=%/medlem=%/redaktion=%/død=% (vent 1/1/4/1)',
      v_anon, v_member, v_redaktion, v_dead_redaktion;
  END IF;

  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: media-mentions gater kilde+mål for anon/medlem og er komplette for redaktion (rullet tilbage)';
  ELSE RAISE; END IF;
END $$;

-- ===== Versionering Task 7b: composite-PK restore-hjælpere (B11/M2) =====
-- T7 dækkede kun enkelt-id (note). Her: family_member (3-kol PK) gennem alle tre
-- helper-stier — fanger ON CONFLICT-constraint-match + multi-kolonne WHERE-cast.
BEGIN;
DO $$
DECLARE
  v_family CONSTANT bigint := -987656221;
  v_person CONSTANT bigint := -987656222;
  cur jsonb;
  pk jsonb := jsonb_build_object(
    'family_id',-987656221,'person_id',-987656222,'rolle','__verify_fm__');
BEGIN
  INSERT INTO family(id,type) VALUES (v_family,'ukendt');
  INSERT INTO person(id,levende,privat) VALUES (v_person,false,false);
  PERFORM _version_upsert_row('family_member',
    jsonb_build_object('family_id',v_family,'person_id',v_person,'rolle','__verify_fm__','ordinal',9,'konfidens','sikker'));
  cur := _version_current_row('family_member', pk);
  IF cur->>'konfidens' <> 'sikker' THEN RAISE EXCEPTION 'FEJL: composite upsert-insert virkede ikke (%)', cur; END IF;
  -- update via ON CONFLICT (samme composite-nøgle)
  PERFORM _version_upsert_row('family_member',
    jsonb_build_object('family_id',v_family,'person_id',v_person,'rolle','__verify_fm__','ordinal',9,'konfidens','formodet'));
  cur := _version_current_row('family_member', pk);
  IF cur->>'konfidens' <> 'formodet' THEN RAISE EXCEPTION 'FEJL: composite upsert-update virkede ikke (%)', cur; END IF;
  PERFORM _version_delete_row('family_member', pk);
  IF _version_current_row('family_member', pk) IS NOT NULL THEN RAISE EXCEPTION 'FEJL: composite delete virkede ikke'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: composite-PK restore-hjælpere round-trip';
  ELSE RAISE; END IF;
END $$;
ROLLBACK;

-- ===== Versionering Task 8c: non-person restore (tom v_pids — regen-loop no-op) =====
-- Alle øvrige restore-asserts rørte en person. Her: undo en kilde-oprettelse (ingen person,
-- ingen conclusion) → v_pids tom → FOREACH IN ARRAY NULL skal være no-op, ikke fejle.
DO $$
DECLARE v_sid bigint; cs bigint;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  v_sid := red_opret_kilde('__verify_kilde__', NULL, NULL, false);
  SELECT max(id) INTO cs FROM change_set;
  IF NOT EXISTS (SELECT 1 FROM source WHERE id=v_sid) THEN RAISE EXCEPTION 'FEJL: kilde ikke oprettet'; END IF;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(cs, false);
  IF EXISTS (SELECT 1 FROM source WHERE id=v_sid) THEN RAISE EXCEPTION 'FEJL: non-person restore slettede ikke kilden'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: non-person restore (tom regen-loop) virker';
  ELSE RAISE; END IF;
END $$;

-- ===== Review 09 H1: DELETE-inverse divergens-tjek (PK-genbrug) =====
-- Bekræfter at restore afviser når en slettet PK er genbrugt af en fremmed række
-- (uden force), og kun overskriver med force. Ville have fanget review09 H1.
DO $$
DECLARE v_nid bigint; cs bigint; cur text; afvist boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  v_nid := (SELECT coalesce(max(id),0)+1 FROM note);
  cs := (SELECT coalesce(max(id),0)+1 FROM change_set);
  INSERT INTO change_set(id,operation,summary,subjekt_synlighed) VALUES (cs,'t','slet note','offentlig');
  INSERT INTO change_event(id,change_set_id,seq,tabel,row_pk,op,foer,efter)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM change_event), cs, 1, 'note',
            jsonb_build_object('id',v_nid),'DELETE',
            jsonb_build_object('id',v_nid,'target_type','person','target_id',1,'indhold','GAMMEL','privat',false), NULL);
  INSERT INTO note(id,target_type,target_id,indhold,privat) VALUES (v_nid,'person',1,'FREMMED-NY',false);
  -- uden force: skal afvise
  BEGIN PERFORM red_fortryd_change_set(cs, false);
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%nyere ændring rører%' THEN afvist := true; ELSE RAISE; END IF; END;
  IF NOT afvist THEN RAISE EXCEPTION 'FEJL: DELETE-inverse afviste ikke PK-genbrug'; END IF;
  IF (SELECT indhold FROM note WHERE id=v_nid) <> 'FREMMED-NY' THEN
    RAISE EXCEPTION 'FEJL: fremmed række blev rørt trods afvisning'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review09 H1 — DELETE-inverse afviser PK-genbrug';
  ELSE RAISE; END IF;
END $$;

-- ===== Review 09 H2: restore bevarer skip_cols (profiles email/rolle) =====
-- End-to-end: slet en profil-bundet person, fortryd → profilen genskabes med
-- rolle/email intakt (ikke NULL-crash). Ville have fanget review09 H2.
DO $$
DECLARE v_uid uuid := '00000000-0000-0000-0000-000000000077'; v_pid bigint; cs bigint; r_after text; e_after text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  v_pid := red_opret_person('__verify_h2__','mand',false,NULL,NULL,NULL);
  -- bind en profil til personen
  INSERT INTO auth.users(id,email) VALUES (v_uid,'medlem@x') ON CONFLICT DO NOTHING;
  INSERT INTO profiles(id,rolle,email,reventlow_person_id) VALUES (v_uid,'medlem','medlem@x',v_pid)
    ON CONFLICT (id) DO UPDATE SET rolle='medlem', email='medlem@x', reventlow_person_id=v_pid;
  -- slet personen (nulstiller profiles.reventlow_person_id → logget UPDATE)
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_slet_person(v_pid);
  SELECT max(id) INTO cs FROM change_set;
  -- fortryd → må IKKE crashe på rolle NOT NULL, og skal bevare email/rolle
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(cs, false);
  SELECT rolle, email INTO r_after, e_after FROM profiles WHERE id=v_uid;
  IF r_after IS NULL OR e_after IS NULL THEN
    RAISE EXCEPTION 'FEJL: restore nulstillede skip_cols (rolle=%, email=%)', r_after, e_after; END IF;
  IF (SELECT reventlow_person_id FROM profiles WHERE id=v_uid) <> v_pid THEN
    RAISE EXCEPTION 'FEJL: reventlow_person_id ikke genskabt'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review09 H2 — restore bevarer profiles skip_cols';
  ELSE RAISE; END IF;
END $$;

-- ===== samme_som redaktionel identitets-sammenkædning (spec 2026-07-02) =====
-- End-to-end: red_samme_som skaber relation+assertion+afklaret-conclusion; idempotent; triggeren
-- afviser G3 multi-sink; red_fjern_samme_som fjerner al evidens. Ruller tilbage.
DO $$
DECLARE a bigint; b bigint; c bigint; rel bigint; rel2 bigint; n_ass int; n_con int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true); a := red_opret_person('__ss_a__','mand',false,NULL,NULL,NULL);
  PERFORM set_config('app.change_set_id','',true); b := red_opret_person('__ss_b__','mand',false,NULL,NULL,NULL);
  PERFORM set_config('app.change_set_id','',true); c := red_opret_person('__ss_c__','mand',false,NULL,NULL,NULL);
  -- opret a→b
  PERFORM set_config('app.change_set_id','',true); rel := red_samme_som(a,b);
  IF NOT EXISTS(SELECT 1 FROM relation WHERE id=rel AND rolle='samme_som' AND subjekt_id=a AND objekt_id=b) THEN
    RAISE EXCEPTION 'FEJL: samme_som-relation ikke oprettet'; END IF;
  SELECT count(*) INTO n_con FROM conclusion WHERE target_type='relation' AND target_id=rel AND status='afklaret';
  IF n_con <> 1 THEN RAISE EXCEPTION 'FEJL: afklaret conclusion mangler (n=%)', n_con; END IF;
  -- idempotens: samme retning → samme id
  PERFORM set_config('app.change_set_id','',true); rel2 := red_samme_som(a,b);
  IF rel2 <> rel THEN RAISE EXCEPTION 'FEJL: idempotens brudt (% <> %)', rel2, rel; END IF;
  -- G3 multi-sink: a→c skal afvises af triggeren
  BEGIN
    PERFORM set_config('app.change_set_id','',true); PERFORM red_samme_som(a,c);
    RAISE EXCEPTION 'FEJL: G3 multi-sink accepteret';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'FEJL:%' THEN RAISE; END IF;
    IF SQLERRM !~* 'multi-sink' THEN RAISE EXCEPTION 'FEJL: forkert afvisning: %', SQLERRM; END IF;
  END;
  -- fjern → al evidens væk
  PERFORM set_config('app.change_set_id','',true); PERFORM red_fjern_samme_som(rel);
  SELECT count(*) INTO n_ass FROM assertion WHERE target_type='relation' AND target_id=rel;
  SELECT count(*) INTO n_con FROM conclusion WHERE target_type='relation' AND target_id=rel;
  IF n_ass <> 0 OR n_con <> 0 OR EXISTS(SELECT 1 FROM relation WHERE id=rel) THEN
    RAISE EXCEPTION 'FEJL: fjern efterlod evidens (ass=%, con=%)', n_ass, n_con; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: samme_som — opret/idempotens/G3-multi-sink/fjern virker';
  ELSE RAISE; END IF;
END $$;

-- Task: flere narrativer pr. person (2026-07-03) — skema-shape
DO $$ BEGIN
  IF (SELECT count(*) FROM information_schema.columns WHERE table_name='source' AND column_name='aar')<>1 THEN
    RAISE EXCEPTION 'FEJL: source.aar mangler'; END IF;
  IF (SELECT count(*) FROM information_schema.parameters
      WHERE specific_name IN (SELECT specific_name FROM information_schema.routines WHERE routine_name='red_upsert_narrativ')
        AND parameter_name='p_source_id')<>1 THEN
    RAISE EXCEPTION 'FEJL: red_upsert_narrativ mangler p_source_id'; END IF;
  IF (SELECT count(*) FROM information_schema.parameters
      WHERE specific_name IN (SELECT specific_name FROM information_schema.routines WHERE routine_name='red_opret_kilde')
        AND parameter_name='p_aar')<>1 THEN
    RAISE EXCEPTION 'FEJL: red_opret_kilde mangler p_aar'; END IF;
  RAISE NOTICE 'OK: flere-narrativer skema (source.aar, red_upsert_narrativ.p_source_id, red_opret_kilde.p_aar)';
END $$;

-- ===== Udledt slægtsnavn Task 1: lineage-graf-walkers + cyklus-vagt =====
DO $$
DECLARE v_lineage BIGINT; v_anc BIGINT[];
BEGIN
  IF to_regprocedure('lineage_ancestors(bigint)') IS NULL THEN
    RAISE EXCEPTION 'FEJL: lineage_ancestors mangler';
  END IF;
  IF to_regprocedure('lineage_descendants(bigint)') IS NULL THEN
    RAISE EXCEPTION 'FEJL: lineage_descendants mangler';
  END IF;
  SELECT id, lineage_ancestors(id) INTO v_lineage, v_anc FROM lineage WHERE kode='I' LIMIT 1;
  IF v_anc IS NULL OR array_length(v_anc,1) <> 2 OR v_anc[1] <> v_lineage
     OR NOT EXISTS (
       SELECT 1 FROM lineage
       WHERE id=v_anc[2] AND parent_lineage_id IS NULL AND slaegtsnavn IS NOT NULL
     ) THEN
    RAISE EXCEPTION 'FEJL: lineage_ancestors(I) skal returnere [sig selv, slægts-rod], fik %', v_anc;
  END IF;
  RAISE NOTICE 'OK: lineage_ancestors basal';
END $$;

DO $$
DECLARE v_a BIGINT; v_b BIGINT; v_source BIGINT;
BEGIN
  SELECT id INTO v_source FROM source LIMIT 1;
  v_a := (SELECT coalesce(max(id),0)+1 FROM lineage);
  INSERT INTO lineage(id, source_id, kode, navn) VALUES (v_a, v_source, '__TEST_A', 'Test A');
  v_b := v_a + 1;
  INSERT INTO lineage(id, source_id, kode, navn, parent_lineage_id) VALUES (v_b, v_source, '__TEST_B', 'Test B', v_a);
  BEGIN
    UPDATE lineage SET parent_lineage_id = v_b WHERE id = v_a;  -- ville lukke løkken A→B→A
    RAISE EXCEPTION 'FEJL: cyklus A→B→A blev IKKE afvist';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'FEJL:%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE '%cyklus%' THEN RAISE; END IF;
    RAISE NOTICE 'OK: cyklus A→B→A korrekt afvist (%)', SQLERRM;
  END;
  DELETE FROM lineage WHERE id IN (v_a, v_b);
END $$;

-- ===== Udledt slægtsnavn Task 2: nye kolonner + skip-liste =====
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='lineage' AND column_name='slaegtsnavn') THEN
    RAISE EXCEPTION 'FEJL: lineage.slaegtsnavn mangler';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='person' AND column_name='visning_efternavn') THEN
    RAISE EXCEPTION 'FEJL: person.visning_efternavn mangler';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='person' AND column_name='visning_fuldt_navn') THEN
    RAISE EXCEPTION 'FEJL: person.visning_fuldt_navn mangler';
  END IF;
  RAISE NOTICE 'OK: udledt-slægtsnavn nye kolonner';
END $$;

-- ===== Udledt slægtsnavn Task 3: normalisering + suffiks-match (spec §4.6, 5 eksempler) =====
DO $$
BEGIN
  IF NOT slaegtsnavn_suffiks_match('Detlef von Reventlow', 'Reventlow') THEN
    RAISE EXCEPTION 'FEJL: "Detlef von Reventlow" burde matche "Reventlow" (partikel)';
  END IF;
  IF slaegtsnavn_suffiks_match('X Ahlefeldt', 'Ahlefeldt-Laurvig-Lehn') THEN
    RAISE EXCEPTION 'FEJL: "X Ahlefeldt" må IKKE matche "Ahlefeldt-Laurvig-Lehn" (rod ≠ gren-variant)';
  END IF;
  IF NOT slaegtsnavn_suffiks_match('X Ahlefeldt', 'Ahlefeldt') THEN
    RAISE EXCEPTION 'FEJL: "X Ahlefeldt" burde matche rod "Ahlefeldt"';
  END IF;
  IF slaegtsnavn_suffiks_match('Anna Reventlow Hansen', 'Reventlow') THEN
    RAISE EXCEPTION 'FEJL: "Anna Reventlow Hansen" må IKKE matche (Reventlow er mellemnavn, ikke suffiks)';
  END IF;
  IF NOT slaegtsnavn_suffiks_match('X von Brockdorff', 'von Brockdorff') THEN
    RAISE EXCEPTION 'FEJL: "X von Brockdorff" burde matche fler-ords-efternavnet "von Brockdorff"';
  END IF;
  RAISE NOTICE 'OK: suffiks-token-match (5/5 spec-eksempler)';
END $$;

-- ===== Udledt slægtsnavn Task 4: regen_person_visning-udvidelse =====
DO $$
DECLARE v_source BIGINT; v_lineage BIGINT; v_p BIGINT; v_efternavn TEXT; v_fuldt TEXT;
BEGIN
  SELECT id INTO v_source FROM source LIMIT 1;
  v_lineage := (SELECT coalesce(max(id),0)+1 FROM lineage);
  INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn)
    VALUES (v_lineage, v_source, '__TEST_L', 'Test-linje', '__VERIFY_SLAEGT_TASK4__');

  -- (a) enkelt-fornavn, født medlem uden efternavn i visning_navn
  v_p := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id, visning_navn) VALUES (v_p, 'Conrad');
  INSERT INTO person_external_id(person_id, source_id, linje, nr) VALUES (v_p, v_source, '__TEST_L', 999);
  PERFORM regen_person_visning(v_p);
  SELECT visning_efternavn, visning_fuldt_navn INTO v_efternavn, v_fuldt FROM person WHERE id=v_p;
  IF v_efternavn <> '__VERIFY_SLAEGT_TASK4__' OR v_fuldt <> 'Conrad __VERIFY_SLAEGT_TASK4__' THEN
    RAISE EXCEPTION 'FEJL: (a) enkelt-fornavn — fik efternavn=% fuldt=%', v_efternavn, v_fuldt;
  END IF;

  -- (d) allerede indeholder efternavnet → NULL, uændret visning_navn
  UPDATE person SET visning_navn = 'Detlef von __VERIFY_SLAEGT_TASK4__' WHERE id=v_p;
  PERFORM regen_person_visning(v_p);
  SELECT visning_efternavn, visning_fuldt_navn INTO v_efternavn, v_fuldt FROM person WHERE id=v_p;
  IF v_efternavn IS NOT NULL OR v_fuldt <> 'Detlef von __VERIFY_SLAEGT_TASK4__' THEN
    RAISE EXCEPTION 'FEJL: (d) allerede-efternavn skal give NULL efternavn, fik % / %', v_efternavn, v_fuldt;
  END IF;

  -- (e) indgift-ægtefælle uden external_id → NULL
  DELETE FROM person_external_id WHERE person_id=v_p;
  UPDATE person SET visning_navn='Anna Ingift' WHERE id=v_p;
  PERFORM regen_person_visning(v_p);
  SELECT visning_efternavn, visning_fuldt_navn INTO v_efternavn, v_fuldt FROM person WHERE id=v_p;
  IF v_efternavn IS NOT NULL OR v_fuldt <> 'Anna Ingift' THEN
    RAISE EXCEPTION 'FEJL: (e) indgift skal give NULL efternavn, fik % / %', v_efternavn, v_fuldt;
  END IF;

  DELETE FROM person WHERE id=v_p;
  DELETE FROM lineage WHERE id=v_lineage;
  RAISE NOTICE 'OK: regen_person_visning — (a)/(d)/(e) scenarier';
END $$;

-- Fan-out → karantæne (to distinkte linjer/sources, to distinkte efternavne)
DO $$
DECLARE v_source BIGINT; v_source2 BIGINT; v_l1 BIGINT; v_l3 BIGINT; v_p BIGINT; v_efternavn TEXT;
BEGIN
  SELECT id INTO v_source FROM source LIMIT 1;
  v_l1 := (SELECT coalesce(max(id),0)+1 FROM lineage);
  INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn) VALUES (v_l1, v_source, '__TEST_FO1', 'A', 'Alfa');
  v_p := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id, visning_navn) VALUES (v_p, 'Fanout Person');
  INSERT INTO person_external_id(person_id, source_id, linje, nr) VALUES (v_p, v_source, '__TEST_FO1', 1);

  v_source2 := (SELECT coalesce(max(id),0)+1 FROM source);
  INSERT INTO source(id, slags, titel) VALUES (v_source2, 'DAA-udgave', 'Test-udgave 2');
  v_l3 := v_l1 + 1;
  INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn) VALUES (v_l3, v_source2, '__TEST_FO2', 'B2', 'Beta');
  INSERT INTO person_external_id(person_id, source_id, linje, nr) VALUES (v_p, v_source2, '__TEST_FO2', 1);

  PERFORM regen_person_visning(v_p);
  SELECT visning_efternavn INTO v_efternavn FROM person WHERE id=v_p;
  IF v_efternavn IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: fan-out (2 distinkte efternavne) skal give NULL, fik %', v_efternavn;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM slaegtsnavn_karantaene WHERE person_id=v_p) THEN
    RAISE EXCEPTION 'FEJL: fan-out skal logges i slaegtsnavn_karantaene';
  END IF;
  PERFORM regen_person_visning(v_p);  -- idempotens: karantæne-rækken må ikke duplikeres
  IF (SELECT count(*) FROM slaegtsnavn_karantaene WHERE person_id=v_p) <> 1 THEN
    RAISE EXCEPTION 'FEJL: karantæne-log er ikke idempotent (upsert)';
  END IF;

  DELETE FROM slaegtsnavn_karantaene WHERE person_id=v_p;
  DELETE FROM person_external_id WHERE person_id=v_p;
  DELETE FROM person WHERE id=v_p;
  DELETE FROM lineage WHERE id IN (v_l1, v_l3);
  DELETE FROM source WHERE id=v_source2;
  RAISE NOTICE 'OK: fan-out → karantæne + idempotens';
END $$;

-- ===== Udledt slægtsnavn Task 5: invalidation-triggere (person_external_id + lineage) =====
DO $$
DECLARE v_source BIGINT; v_lineage BIGINT; v_p BIGINT; v_fuldt TEXT;
BEGIN
  SELECT id INTO v_source FROM source LIMIT 1;
  v_lineage := (SELECT coalesce(max(id),0)+1 FROM lineage);
  INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn) VALUES (v_lineage, v_source, '__TEST_TRG', 'Trigger-test', 'Testnavn');
  v_p := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id, visning_navn) VALUES (v_p, 'Trigger Person');

  -- INSERT på person_external_id skal regenerere UDEN eksplicit regen-kald
  INSERT INTO person_external_id(person_id, source_id, linje, nr) VALUES (v_p, v_source, '__TEST_TRG', 1);
  SELECT visning_fuldt_navn INTO v_fuldt FROM person WHERE id=v_p;
  IF v_fuldt <> 'Trigger Person Testnavn' THEN
    RAISE EXCEPTION 'FEJL: person_external_id-INSERT trigger regen ikke, fik fuldt_navn=%', v_fuldt;
  END IF;

  -- UPDATE på lineage.slaegtsnavn skal regenerere undertræets medlemmer UDEN eksplicit regen-kald
  UPDATE lineage SET slaegtsnavn = 'Nytnavn' WHERE id = v_lineage;
  SELECT visning_fuldt_navn INTO v_fuldt FROM person WHERE id=v_p;
  IF v_fuldt <> 'Trigger Person Nytnavn' THEN
    RAISE EXCEPTION 'FEJL: lineage.slaegtsnavn-UPDATE trigger ikke subtræ-regen, fik fuldt_navn=%', v_fuldt;
  END IF;

  DELETE FROM person_external_id WHERE person_id=v_p;
  DELETE FROM person WHERE id=v_p;
  DELETE FROM lineage WHERE id=v_lineage;
  RAISE NOTICE 'OK: invalidation-triggere (person_external_id + lineage)';
END $$;

-- ===== Review 19 H1: frisk lineage-INSERT (ikke kun UPDATE) trigger regen =====
DO $$
DECLARE v_source BIGINT; v_lineage BIGINT; v_p BIGINT; v_fuldt TEXT;
BEGIN
  SELECT id INTO v_source FROM source LIMIT 1;
  v_p := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id, visning_navn) VALUES (v_p, 'Frisk Insert Person');
  v_lineage := (SELECT coalesce(max(id),0)+1 FROM lineage);
  -- external_id INDSAT FØR lineage-rækken findes (matcher load_daa.R → post_load_fixup.R-rækkefølgen).
  INSERT INTO person_external_id(person_id, source_id, linje, nr) VALUES (v_p, v_source, '__TEST_H1', 1);
  -- fresh INSERT (ikke UPDATE) på lineage — skal ALENE trigge regen af v_p uden noget eksplicit kald.
  INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn) VALUES (v_lineage, v_source, '__TEST_H1', 'H1-test', 'Insertnavn');
  SELECT visning_fuldt_navn INTO v_fuldt FROM person WHERE id=v_p;
  IF v_fuldt <> 'Frisk Insert Person Insertnavn' THEN
    RAISE EXCEPTION 'FEJL (review19 H1): lineage-INSERT trigger ikke regen, fik fuldt_navn=%', v_fuldt;
  END IF;
  DELETE FROM person_external_id WHERE person_id=v_p;
  DELETE FROM person WHERE id=v_p;
  DELETE FROM lineage WHERE id=v_lineage;
  RAISE NOTICE 'OK: review19 H1 — frisk lineage-INSERT trigger regen';
END $$;

-- ===== Review 19 H2: red_slet_person for en karantæneret person =====
DO $$
DECLARE v_source BIGINT; v_source2 BIGINT; v_l1 BIGINT; v_l2 BIGINT; v_p BIGINT; v_uid UUID := '00000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM set_config('request.jwt.claim.sub', v_uid::text, true);
  INSERT INTO auth.users(id,email) VALUES (v_uid,'db-verify@test.invalid') ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id, rolle, email) VALUES (v_uid,'redaktion','t@x') ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  SELECT id INTO v_source FROM source LIMIT 1;
  v_l1 := (SELECT coalesce(max(id),0)+1 FROM lineage);
  INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn) VALUES (v_l1, v_source, '__TEST_H2A', 'A', 'Alfa');
  v_source2 := (SELECT coalesce(max(id),0)+1 FROM source);
  INSERT INTO source(id, slags, titel) VALUES (v_source2, 'DAA-udgave', 'Test-udgave H2');
  v_l2 := v_l1 + 1;
  INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn) VALUES (v_l2, v_source2, '__TEST_H2B', 'B', 'Beta');
  v_p := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id, visning_navn) VALUES (v_p, 'H2 Karantæne Person');
  INSERT INTO person_external_id(person_id, source_id, linje, nr) VALUES (v_p, v_source, '__TEST_H2A', 1);
  INSERT INTO person_external_id(person_id, source_id, linje, nr) VALUES (v_p, v_source2, '__TEST_H2B', 1);
  PERFORM regen_person_visning(v_p);
  IF NOT EXISTS (SELECT 1 FROM slaegtsnavn_karantaene WHERE person_id=v_p) THEN
    RAISE EXCEPTION 'FEJL (review19 H2 setup): person burde være i karantæne';
  END IF;
  -- red_slet_person MÅ IKKE fejle (FK-violation) selvom personen er i karantæne.
  PERFORM red_slet_person(v_p);
  IF EXISTS (SELECT 1 FROM person WHERE id=v_p) OR EXISTS (SELECT 1 FROM slaegtsnavn_karantaene WHERE person_id=v_p) THEN
    RAISE EXCEPTION 'FEJL (review19 H2): red_slet_person efterlod rester for en karantæneret person';
  END IF;
  DELETE FROM lineage WHERE id IN (v_l1, v_l2);
  DELETE FROM source WHERE id=v_source2;
  RAISE NOTICE 'OK: review19 H2 — red_slet_person virker for karantæneret person';
END $$;


-- ===== Task 12: media rettigheds-gating + storage.objects-mapping (mediehåndtering 2026-07-04) =====
-- Verificerer den ANDEN gating-dimension (copyright/publikation), ortogonal til afbildet-gatingen:
--   · objekt-foto, maa_publiceres=false → SKJULT for anon OG medlem, men SYNLIGT for redaktion
--   · objekt-foto, maa_publiceres=true men upload_status='kladde' → SKJULT (kun 'klar' publiceres)
--   · objekt-foto, maa_publiceres=true + 'klar' → SYNLIGT for anon
-- Plus storage-objekt→media-mappingen (media_id_for_object) inkl. forældreløst objekt → fail-closed.
DO $$
DECLARE vis_spaerret int; vis_kladde int; vis_klar int; vis_red int;
        map_hit bigint; map_orphan bigint; ok_orphan boolean;
        obj_klar boolean; obj_spaerret boolean; obj_orphan boolean;
        skjult_naegtet boolean; mapping_naegtet boolean;
BEGIN
  DELETE FROM media WHERE id IN (-911,-912,-913);
  INSERT INTO media(id, slags, titel, maa_publiceres, upload_status, bucket, storage_path) VALUES
    (-911,'segl','objekt-spaerret', false,'klar',   'media','test/spaerret.jpg'),
    (-912,'segl','objekt-kladde',   true, 'kladde', 'media','test/kladde.jpg'),
    (-913,'segl','objekt-klar',     true, 'klar',   'media','test/klar.jpg');

  SET LOCAL ROLE anon;
  SELECT count(*) INTO vis_spaerret FROM media WHERE id = -911;
  SELECT count(*) INTO vis_kladde   FROM media WHERE id = -912;
  SELECT count(*) INTO vis_klar     FROM media WHERE id = -913;

  -- Medie-indkapslingen (2026-09-19): anons LOVLIGE vej fra storage-sti til synlighed er
  -- wrapperen media_object_synlig_anon, som er SECURITY DEFINER og derfor slår op og gater
  -- som ejeren. Samme svar som rettigheds-gatingen ovenfor, nu målt fra sti-siden.
  SELECT public.media_object_synlig_anon('test/klar.jpg'),
         public.media_object_synlig_anon('test/spaerret.jpg'),
         public.media_object_synlig_anon('findes/ikke.jpg')
    INTO obj_klar, obj_spaerret, obj_orphan;
  -- ... og de to indkapslede funktioner maa IKKE laengere kunne kaldes direkte af anon.
  -- media_afbilder_skjult var et PII-orakel ("afbilder billede N en levende person?"),
  -- media_id_for_object et eksistens-orakel over storage-stier. Paastandene laaser
  -- indkapslingen fast, saa et genudstedt grant fanges her i stedet for i prod.
  BEGIN
    PERFORM public.media_afbilder_skjult(-913);
    skjult_naegtet := false;
  EXCEPTION WHEN insufficient_privilege THEN
    skjult_naegtet := true;
  END;
  BEGIN
    PERFORM public.media_id_for_object('test/klar.jpg');
    mapping_naegtet := false;
  EXCEPTION WHEN insufficient_privilege THEN
    mapping_naegtet := true;
  END;
  RESET ROLE;

  IF NOT (vis_spaerret = 0 AND vis_kladde = 0 AND vis_klar = 1) THEN
    RAISE EXCEPTION 'rettigheds-gating FEJL (anon): spaerret=% (vent 0), kladde=% (vent 0), klar=% (vent 1)',
      vis_spaerret, vis_kladde, vis_klar;
  END IF;

  IF NOT (obj_klar AND NOT obj_spaerret AND NOT obj_orphan AND skjult_naegtet AND mapping_naegtet) THEN
    RAISE EXCEPTION 'medie-indkapsling FEJL: sti-wrapper klar=% (vent t), spaerret=% (vent f), foraeldreloes=% (vent f) | direkte kald naegtet: afbilder_skjult=%, id_for_object=% (vent t,t)',
      obj_klar, obj_spaerret, obj_orphan, skjult_naegtet, mapping_naegtet;
  END IF;

  -- objekt→media-mapping: kendt sti resolver, ukendt (forældreløs) → NULL → rettigheder_ok=false
  SELECT public.media_id_for_object('test/klar.jpg')        INTO map_hit;
  SELECT public.media_id_for_object('findes/ikke.jpg')      INTO map_orphan;
  SELECT public.media_rettigheder_ok(public.media_id_for_object('findes/ikke.jpg')) INTO ok_orphan;
  IF map_hit IS DISTINCT FROM -913 OR map_orphan IS NOT NULL OR ok_orphan IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'storage-mapping FEJL: hit=% (vent -913), orphan=% (vent NULL), orphan_ok=% (vent false)',
      map_hit, map_orphan, ok_orphan;
  END IF;

  DELETE FROM media WHERE id IN (-911,-912,-913);
  RAISE NOTICE 'OK: media rettigheds-gating (spærret/kladde skjult, klar synlig) + storage-mapping (forældreløs fail-closed) + medie-indkapsling (sti-wrapper virker, direkte gate-kald lukket)';
END $$;


-- ===== Task 12b: storage.objects-POLITIKKER under faktiske roller (ikke kun helper-kald) =====
-- Task 12 tester media-TABELLEN + helperne. Denne blok udøver de rigtige storage.objects-politikker
-- (media_obj_anon/auth) ved at indsætte objekt-rækker og læse dem under SET LOCAL ROLE — så en
-- fail-open-politik (OR i stedet for AND, manglende rettigheds-gate, eller manglende bucket-guard)
-- rejser her. Springes over hvis der ikke findes en 'media'-bucket (lokalt/pre-provisionering).
BEGIN;
DO $$
DECLARE has_bucket boolean; vis_klar int; vis_spaerret int; vis_orphan int; vis_klar_auth int; vis_spaerret_auth int;
        vis_levende int; vis_levende_auth int; vis_anden_bucket int;
BEGIN
  IF to_regclass('storage.buckets') IS NULL OR to_regclass('storage.objects') IS NULL THEN
    RAISE NOTICE 'SPRINGER OVER Task 12b (storage.objects-politikker): storage-katalog er ikke installeret';
    RETURN;
  END IF;
  SELECT EXISTS(SELECT 1 FROM storage.buckets WHERE id='media') INTO has_bucket;
  IF NOT has_bucket THEN
    RAISE NOTICE 'SPRINGER OVER Task 12b (storage.objects-politikker): ingen media-bucket — opret den for fuld dækning';
    RETURN;
  END IF;
  IF EXISTS (
    SELECT 1 FROM storage.objects
    WHERE (bucket_id='media' AND name IN ('test/klar.jpg','test/spaerret.jpg','test/orphan.jpg','test/levende.jpg'))
       OR bucket_id='__test_anden_bucket'
  ) OR EXISTS (SELECT 1 FROM media WHERE id IN (-921,-922,-923))
    OR EXISTS (SELECT 1 FROM person WHERE id = -923)
    OR EXISTS (SELECT 1 FROM relation WHERE id = -923)
    OR EXISTS (SELECT 1 FROM storage.buckets WHERE id='__test_anden_bucket') THEN
    RAISE EXCEPTION 'storage.objects-gating fixture-kollision';
  END IF;
  -- Et --no-acl restore har bevidst ingen Supabase-default-grants. De
  -- midlertidige grants rulles tilbage og lader testen udøve RLS-politikkerne.
  EXECUTE 'GRANT USAGE ON SCHEMA storage TO anon, authenticated';
  EXECUTE 'GRANT SELECT ON storage.objects TO anon, authenticated';
  INSERT INTO media(id, slags, titel, maa_publiceres, upload_status, bucket, storage_path) VALUES
    (-921,'segl','obj-klar',    true, 'klar','media','test/klar.jpg'),
    (-922,'segl','obj-spaerret',false,'klar','media','test/spaerret.jpg'),
    -- -923 er rettigheds-MAESSIGT frigivet, men afbilder en levende person. Den skiller de to
    -- ortogonale dimensioner ad: uden denne fixture ville en regression, hvor politikken kun
    -- gater paa rettigheder, forblive groen (Codex-fund 2026-09-20).
    (-923,'foto','obj-levende', true, 'klar','media','test/levende.jpg');
  INSERT INTO person(id, levende, privat) VALUES (-923, true, false);
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle)
    VALUES (-923,'person',-923,'media',-923,'afbildet');
  -- En ANDEN bucket med et objekt, der hedder praecis det samme som et synligt media-objekt.
  -- Uden bucket-vagten i politikken ville wrapperen svare true og aabne det (samme fund).
  INSERT INTO storage.buckets(id, name) VALUES ('__test_anden_bucket','__test_anden_bucket');
  INSERT INTO storage.objects(bucket_id, name) VALUES
    ('media','test/klar.jpg'), ('media','test/spaerret.jpg'), ('media','test/orphan.jpg'), -- orphan = ingen media-række
    ('media','test/levende.jpg'),
    ('__test_anden_bucket','test/klar.jpg');

  SET LOCAL ROLE anon;
  SELECT count(*) INTO vis_klar     FROM storage.objects WHERE bucket_id='media' AND name='test/klar.jpg';
  SELECT count(*) INTO vis_spaerret FROM storage.objects WHERE bucket_id='media' AND name='test/spaerret.jpg';
  SELECT count(*) INTO vis_orphan   FROM storage.objects WHERE bucket_id='media' AND name='test/orphan.jpg';
  SELECT count(*) INTO vis_levende  FROM storage.objects WHERE bucket_id='media' AND name='test/levende.jpg';
  SELECT count(*) INTO vis_anden_bucket FROM storage.objects WHERE bucket_id='__test_anden_bucket';
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO vis_klar_auth     FROM storage.objects WHERE bucket_id='media' AND name='test/klar.jpg';
  SELECT count(*) INTO vis_spaerret_auth FROM storage.objects WHERE bucket_id='media' AND name='test/spaerret.jpg';
  SELECT count(*) INTO vis_levende_auth  FROM storage.objects WHERE bucket_id='media' AND name='test/levende.jpg';
  RESET ROLE;

  IF NOT (vis_klar=1 AND vis_spaerret=0 AND vis_orphan=0 AND vis_levende=0 AND vis_anden_bucket=0
          AND vis_klar_auth=1 AND vis_spaerret_auth=0 AND vis_levende_auth=0) THEN
    RAISE EXCEPTION 'storage.objects-gating FEJL: anon(klar=% [1], spaerret=% [0], orphan=% [0], levende=% [0], anden bucket=% [0]), medlem(klar=% [1], spaerret=% [0], levende=% [0])',
      vis_klar, vis_spaerret, vis_orphan, vis_levende, vis_anden_bucket,
      vis_klar_auth, vis_spaerret_auth, vis_levende_auth;
  END IF;

  RAISE NOTICE 'OK: storage.objects-politikker (klar synlig anon+medlem; spærret, forældreløs, GDPR-skjult og anden bucket skjult for begge)';
END $$;
ROLLBACK;

-- ===== Task 13: generations-reparation — slægtled-kolonner findes + trigger scoped =====
DO $$
BEGIN
  ASSERT (SELECT count(*) FROM information_schema.columns
          WHERE table_name='person_external_id'
            AND column_name IN ('slaegtled_lokal','slaegtled_gennem','kuld')) = 3,
    'Mangler generations-kolonner på person_external_id';
END $$;

-- Trigger-scoping: trg_external_id_regen skal være kolonne-scoped (UPDATE OF
-- person_id, source_id, linje, nr), IKKE et bart "AFTER UPDATE" — ellers
-- fyrer den unødigt på slaegtled_lokal/slaegtled_gennem/kuld-opdateringer
-- (backfill_slaegtled.R), som ikke selv skal trigge lineage-regen.
DO $$
DECLARE
  def text;
BEGIN
  SELECT pg_get_triggerdef(oid) INTO def
    FROM pg_trigger
   WHERE tgname = 'trg_external_id_regen' AND NOT tgisinternal;
  ASSERT def IS NOT NULL, 'trg_external_id_regen findes ikke';
  ASSERT position('UPDATE OF' in def) > 0,
    'trg_external_id_regen er ikke kolonne-scoped (mangler UPDATE OF) — fyrer på ALLE updates';
  ASSERT position('linje' in def) > 0 AND position('nr' in def) > 0,
    'trg_external_id_regen UPDATE OF-liste mangler linje/nr-kolonner';
  RAISE NOTICE 'OK: trg_external_id_regen er kolonne-scoped (%)', def;
END $$;


-- ===== Task 14: bookmark — RLS-isolation, dublet-sikring, anon-lukket, cascade =====
DO $$
DECLARE cnt_a int; cnt_b int; insert_denied boolean := false; anon_denied boolean := false;
BEGIN
  INSERT INTO auth.users(id,email) VALUES
    ('00000000-0000-0000-0000-0000000000a1','a@test'),
    ('00000000-0000-0000-0000-0000000000a2','b@test')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO person(id) VALUES (-931),(-932) ON CONFLICT (id) DO NOTHING;

  -- Bruger A gemmer -931
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',true);
  SET LOCAL ROLE authenticated;
  INSERT INTO bookmark(person_id) VALUES (-931);
  SELECT count(*) INTO cnt_a FROM bookmark WHERE person_id=-931;
  RESET ROLE;

  -- Bruger B ser IKKE A's bogmærke; forsøg på at skrive i A's navn afvises
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a2',true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO cnt_b FROM bookmark WHERE person_id=-931;
  BEGIN
    INSERT INTO bookmark(user_id, person_id) VALUES ('00000000-0000-0000-0000-0000000000a1', -932);
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN insert_denied := true;
  END;
  RESET ROLE;

  -- Anon kan hverken læse eller skrive: INGEN grant overhovedet (stærkere end RLS-filtrering —
  -- dual-review N1), så selv et bart SELECT rejser permission denied, ikke et tomt resultat.
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM 1 FROM bookmark WHERE person_id=-931;
  EXCEPTION WHEN insufficient_privilege THEN anon_denied := true;
  END;
  RESET ROLE;

  IF cnt_a <> 1 THEN RAISE EXCEPTION 'FEJL: bruger A ser ikke eget bogmærke (fik %)', cnt_a; END IF;
  IF cnt_b <> 0 THEN RAISE EXCEPTION 'FEJL: RLS-læk — bruger B ser bruger A''s bogmærke'; END IF;
  IF NOT insert_denied THEN RAISE EXCEPTION 'FEJL: WITH CHECK afviste ikke insert i fremmed navn'; END IF;
  IF NOT anon_denied THEN RAISE EXCEPTION 'FEJL: anon kunne læse bookmark uden grant (vent permission denied)'; END IF;

  -- Dubletsikring: samme (user,person) igen = no-op
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',true);
  SET LOCAL ROLE authenticated;
  INSERT INTO bookmark(person_id) VALUES (-931) ON CONFLICT (user_id,person_id) DO NOTHING;
  RESET ROLE;

  -- Cascade: slet person -931 → bogmærket forsvinder
  DELETE FROM person WHERE id=-931;
  IF EXISTS (SELECT 1 FROM bookmark WHERE person_id=-931) THEN
    RAISE EXCEPTION 'FEJL: bookmark overlevede person-sletning (cascade virkede ikke)';
  END IF;

  DELETE FROM bookmark WHERE person_id IN (-931,-932);
  DELETE FROM person WHERE id IN (-931,-932);
  DELETE FROM auth.users WHERE id IN ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000a2');
  RAISE NOTICE 'OK: bookmark RLS-isolation (egen-læs, fremmed-skriv afvist, anon blokeret) + cascade + dubletsikring';
END $$;

-- ===== ikke_samme_som — persisteret identitets-afvisning (tværudgave-spec §4) =====
-- Kræver redaktion-kontekst (auth.uid() → redaktion-profil). Lokalt: sæt
-- request.jwt.claim.sub; i Supabase SQL Editor kør som funktionsejer (jf. Task 4-note).
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001', false);
DO $$
DECLARE r_ikke bigint; r_samme bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN
    RAISE NOTICE 'SPRINGER OVER ikke_samme_som-verify: ikke redaktion-kontekst'; RETURN; END IF;
  INSERT INTO person(id, levende, koen) VALUES (-1001,false,'mand'),(-1002,false,'kvinde') ON CONFLICT (id) DO NOTHING;

  -- evidens-triple + normalisering + INGEN citation
  r_ikke := red_ikke_samme_som(-1001,-1002);
  IF NOT EXISTS(SELECT 1 FROM relation WHERE id=r_ikke AND rolle='ikke_samme_som'
      AND subjekt_id=least(-1001,-1002) AND objekt_id=greatest(-1001,-1002))
     OR NOT EXISTS(SELECT 1 FROM assertion WHERE target_type='relation' AND target_id=r_ikke)
     OR NOT EXISTS(SELECT 1 FROM conclusion WHERE target_type='relation' AND target_id=r_ikke AND status='afklaret')
     OR EXISTS(SELECT 1 FROM citation WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='relation' AND target_id=r_ikke))
  THEN RAISE EXCEPTION 'ikke_samme_som: evidens-triple/normalisering/citation-fri fejlede'; END IF;

  -- idempotens begge retninger
  IF red_ikke_samme_som(-1002,-1001) <> r_ikke THEN RAISE EXCEPTION 'ikke_samme_som: idempotens fejlede'; END IF;

  -- self afvist
  BEGIN PERFORM red_ikke_samme_som(-1001,-1001); RAISE EXCEPTION 'self ikke afvist';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%sig selv%' THEN RAISE; END IF; END;

  -- kontradiktion begge veje
  PERFORM red_fjern_ikke_samme_som(r_ikke);
  r_samme := red_samme_som(-1001,-1002);
  BEGIN PERFORM red_ikke_samme_som(-1001,-1002); RAISE EXCEPTION 'samme_som→ikke ikke fanget';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%IDENTITY_COMPONENT_CONTRADICTION%' THEN RAISE; END IF; END;
  PERFORM red_fjern_samme_som(r_samme);
  r_ikke := red_ikke_samme_som(-1001,-1002);
  BEGIN PERFORM red_samme_som(-1001,-1002); RAISE EXCEPTION 'ikke→samme ikke fanget';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%IDENTITY_COMPONENT_CONTRADICTION%'
       AND SQLERRM NOT LIKE '%er markeret ikke_samme_som%' THEN RAISE; END IF;
  END;

  -- red_relation-guard + fjern sletter evidens
  BEGIN PERFORM red_relation('person',-1001,'person',-1002,'ikke_samme_som'); RAISE EXCEPTION 'red_relation tillod ikke_samme_som';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%red_ikke_samme_som%' THEN RAISE; END IF; END;
  PERFORM red_fjern_ikke_samme_som(r_ikke);
  IF EXISTS(SELECT 1 FROM relation WHERE id=r_ikke) THEN RAISE EXCEPTION 'fjern slettede ikke relationen'; END IF;

  DELETE FROM person WHERE id IN (-1001,-1002);
  RAISE NOTICE 'OK: ikke_samme_som (evidens-triple, idempotens, self, kontradiktion begge veje, red_relation-guard, fjern)';
END $$;

-- drift-assert: intet person-par har BÅDE samme_som og ikke_samme_som
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM relation s JOIN relation i
      ON i.rolle='ikke_samme_som' AND s.rolle='samme_som'
     AND least(s.subjekt_id,s.objekt_id)=i.subjekt_id AND greatest(s.subjekt_id,s.objekt_id)=i.objekt_id
    WHERE s.subjekt_type='person' AND s.objekt_type='person')
  THEN RAISE EXCEPTION 'DRIFT: par med både samme_som og ikke_samme_som'; END IF;
  RAISE NOTICE 'OK: ingen samme_som/ikke_samme_som-drift';
END $$;

-- ===== Problem 2 — konkurrerende forældrefamilie-påstande (spec §10, RPC/constraint/guard) =====
-- Syntetiske negativ-id-fixtures (rører ikke rigtige data). Backfill-komplethed + global P1-drift
-- verificeres separat mod ren single-edition-bed (multi-edition daa_test2 ville falsk-bestå, se docs/reviews/29).
DO $$
DECLARE
  v jsonb; a1 bigint; a2 bigint; v_fam bigint; v_status text; v_konf text; v_valgt bigint; v_slotfact bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN
    RAISE NOTICE 'SPRINGER OVER forældre-konflikt-verify: ikke redaktion-kontekst'; RETURN; END IF;

  -- Defensiv oprydning FØR (så re-runs efter en halv-fejlet kørsel er sikre — og family_member
  -- kan indsættes plain: den DEFERRABLE EXCLUDE kan ikke bruges som ON CONFLICT-arbiter).
  DELETE FROM conclusion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-2001);
  DELETE FROM citation WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-2001));
  DELETE FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-2001);
  DELETE FROM fact WHERE subjekt_type='person' AND subjekt_id=-2001;
  DELETE FROM family_member WHERE person_id IN (-2001,-2002,-2003,-2004,-2005) OR family_id IN (-3001,-3002,-3099);
  DELETE FROM family WHERE id IN (-3001,-3002,-3099);
  DELETE FROM person WHERE id IN (-2001,-2002,-2003,-2004,-2005);
  DELETE FROM source WHERE id IN (-9001,-9002);

  -- fixtures: barn -2001; udgave-1-familie -3001 (partnere -2002/-2003); udgave-2-familie -3002 (-2004/-2005);
  -- -3099 = tom familie til rå-EXCLUDE-test. Barn starter projiceret i -3001 (udgave 1's graf).
  INSERT INTO person(id, levende, koen) VALUES
    (-2001,false,'mand'),(-2002,false,'mand'),(-2003,false,'kvinde'),(-2004,false,'mand'),(-2005,false,'kvinde');
  INSERT INTO family(id, type) VALUES (-3001,'vielse'),(-3002,'vielse'),(-3099,'vielse');
  INSERT INTO family_member(family_id, person_id, rolle) VALUES
    (-3001,-2002,'partner'),(-3001,-2003,'partner'),(-3002,-2004,'partner'),(-3002,-2005,'partner'),(-3001,-2001,'barn');
  INSERT INTO source(id, udgave) VALUES (-9001,'TEST udgave 1'),(-9002,'TEST udgave 2');

  -- (a) selv-helende korroboration: påstand matcher barnets projicerede række → afklaret, ingen konflikt.
  v := red_tilfoej_foraeldre_paastand(-2001, -3001, -9001, 's.1', 'udg1 citat');
  a1 := (v->>'assertion_id')::bigint;
  v_slotfact := (v->>'fact_id')::bigint;
  IF (v->>'konflikt')::boolean THEN RAISE EXCEPTION 'a: selv-helende gav konflikt'; END IF;
  IF NOT EXISTS(SELECT 1 FROM assertion WHERE id=a1 AND objekt_type='family' AND objekt_id=-3001 AND vaerdi_tekst='barn')
     OR NOT EXISTS(SELECT 1 FROM citation WHERE assertion_id=a1 AND source_id=-9001)
     OR NOT EXISTS(SELECT 1 FROM conclusion WHERE target_type='fact' AND target_id=v_slotfact AND valgt_assertion_id=a1 AND status='afklaret')
  THEN RAISE EXCEPTION 'a: evidens-tripel/afklaret-konklusion fejlede'; END IF;

  -- (b) idempotens: samme familie + samme kilde → samme id'er, intet nyt.
  v := red_tilfoej_foraeldre_paastand(-2001, -3001, -9001);
  IF (v->>'assertion_id')::bigint <> a1 OR NOT (v->>'idempotent')::boolean THEN RAISE EXCEPTION 'b: idempotens fejlede'; END IF;

  -- (c) korroboration fra ANDEN kilde (samme familie) → ekstra påstand, stadig afklaret, ingen konflikt.
  v := red_tilfoej_foraeldre_paastand(-2001, -3001, -9002, 's.5', 'udg2 enig');
  IF (v->>'konflikt')::boolean THEN RAISE EXCEPTION 'c: korroboration gav konflikt'; END IF;
  IF (SELECT status FROM conclusion WHERE target_type='fact' AND target_id=v_slotfact) <> 'afklaret'
  THEN RAISE EXCEPTION 'c: status ikke afklaret efter korroboration'; END IF;

  -- (d) konflikt: rival peger på anden familie → omstridt + konfidens-eskalering, valgt URØRT.
  v := red_tilfoej_foraeldre_paastand(-2001, -3002, -9002, 's.9', 'udg2 anden far');
  a2 := (v->>'assertion_id')::bigint;
  IF NOT (v->>'konflikt')::boolean THEN RAISE EXCEPTION 'd: konflikt ikke detekteret'; END IF;
  SELECT status, valgt_assertion_id INTO v_status, v_valgt FROM conclusion WHERE target_type='fact' AND target_id=v_slotfact;
  IF v_status <> 'omstridt' THEN RAISE EXCEPTION 'd: status ikke omstridt'; END IF;
  IF v_valgt <> a1 THEN RAISE EXCEPTION 'd: valgt_assertion_id blev rørt (skal pege på udgave 1)'; END IF;
  IF (SELECT konfidens FROM family_member WHERE person_id=-2001 AND rolle='barn' AND family_id=-3001) <> 'omstridt'
  THEN RAISE EXCEPTION 'd: barn-rækkens konfidens ikke eskaleret til omstridt'; END IF;

  -- (e) konflikt-view rapporterer to distinkte familier.
  IF NOT EXISTS(SELECT 1 FROM red_foraeldre_konflikt WHERE person_id=-2001 AND antal_familier=2 AND status='omstridt')
  THEN RAISE EXCEPTION 'e: red_foraeldre_konflikt viste ikke konflikten'; END IF;

  -- (f) adjudikér udgave 2: re-peg + flyt projektion + konfidens sat, i ét kald. P1 holder.
  PERFORM red_vaelg_foraeldre(a2, 'sikker');
  SELECT valgt_assertion_id, status INTO v_valgt, v_status FROM conclusion WHERE target_type='fact' AND target_id=v_slotfact;
  IF v_valgt <> a2 OR v_status <> 'afklaret' THEN RAISE EXCEPTION 'f: konklusion ikke re-pegget/afklaret'; END IF;
  SELECT family_id INTO v_fam FROM family_member WHERE person_id=-2001 AND rolle='barn';
  IF v_fam <> -3002 THEN RAISE EXCEPTION 'f: barn ikke flyttet til udgave-2-familie (P1)'; END IF;
  IF (SELECT konfidens FROM family_member WHERE person_id=-2001 AND rolle='barn') <> 'sikker'
  THEN RAISE EXCEPTION 'f: konfidens ikke sat'; END IF;

  -- (g) skift tilbage til udgave 1: flytter projektion tilbage (begge påstande stadig bevaret).
  PERFORM red_vaelg_foraeldre(a1);
  SELECT family_id INTO v_fam FROM family_member WHERE person_id=-2001 AND rolle='barn';
  IF v_fam <> -3001 THEN RAISE EXCEPTION 'g: barn ikke flyttet tilbage til udgave 1'; END IF;
  IF (SELECT count(*) FROM assertion WHERE target_type='fact' AND target_id=v_slotfact AND objekt_type='family') < 2
  THEN RAISE EXCEPTION 'g: en påstand gik tabt ved adjudikation'; END IF;

  -- (h) forældre_ukendt-kontradiktion: markér, forsøg vælg → RAISE; tilbagetræk, retry virker.
  v := red_upsert_fakta('person',-2001,'forældre_ukendt','ukendt');
  BEGIN PERFORM red_vaelg_foraeldre(a2); RAISE EXCEPTION 'h: forældre_ukendt-guard fyrede ikke';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%forældre_ukendt%' THEN RAISE; END IF; END;
  PERFORM red_tilbagetraek_fakta((v->>'fact_id')::bigint);
  PERFORM red_vaelg_foraeldre(a1);  -- virker igen

  -- (i) guards: de tre fakta-RPC'er afviser 'forældrefamilie'.
  BEGIN PERFORM red_upsert_fakta('person',-2001,'forældrefamilie','x'); RAISE EXCEPTION 'i: red_upsert_fakta tillod forældrefamilie';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%red_tilfoej_foraeldre_paastand%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_opret_fakta('person',-2001,'forældrefamilie','x'); RAISE EXCEPTION 'i: red_opret_fakta tillod forældrefamilie';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%red_tilfoej_foraeldre_paastand%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_tilfoej_oplysning(v_slotfact,'x'); RAISE EXCEPTION 'i: red_tilfoej_oplysning tillod forældrefamilie-slot';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%red_tilfoej_foraeldre_paastand%' THEN RAISE; END IF; END;

  -- (i2) konklusions-dørene afviser forældrefamilie-slottet (lukker P1-hullet: re-peg uden projektion).
  BEGIN PERFORM red_set_konklusion(a1); RAISE EXCEPTION 'i2: red_set_konklusion tillod forældrefamilie-slot';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%red_vaelg_foraeldre%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_edit_oplysning(a1,'x'); RAISE EXCEPTION 'i2: red_edit_oplysning tillod forældrefamilie-slot';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%uforanderlige%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_slet_oplysning(a1); RAISE EXCEPTION 'i2: red_slet_oplysning tillod forældrefamilie-slot';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%uforanderlige%' THEN RAISE; END IF; END;

  -- (j) red_tilfoej_barn venligt prætjek: barn har allerede fødselsfamilie (-3001) → venlig fejl.
  BEGIN PERFORM red_tilfoej_barn(-3002, -2001); RAISE EXCEPTION 'j: red_tilfoej_barn tillod anden fødselsfamilie';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%allerede en fødselsfamilie%' THEN RAISE; END IF; END;

  -- (k) rå EXCLUDE-værn: direkte INSERT af en anden 'barn'-række afvises (deferred → tving med SET CONSTRAINTS).
  BEGIN
    INSERT INTO family_member(family_id, person_id, rolle) VALUES (-3099, -2001, 'barn');
    SET CONSTRAINTS family_member_en_foedselsfamilie IMMEDIATE;
    RAISE EXCEPTION 'k: EXCLUDE tillod to fødselsfamilier';
  EXCEPTION WHEN exclusion_violation THEN NULL; END;

  -- P1 lokal-invariant: afklaret slot ⇒ valgt assertions objekt_id = barn-rækkens family_id.
  IF EXISTS(
    SELECT 1 FROM conclusion c JOIN assertion aa ON aa.id=c.valgt_assertion_id
    WHERE c.target_type='fact' AND c.target_id=v_slotfact AND c.status='afklaret'
      AND aa.objekt_id <> (SELECT family_id FROM family_member WHERE person_id=-2001 AND rolle='barn'))
  THEN RAISE EXCEPTION 'P1: valgt slot-familie ≠ projiceret barn-række'; END IF;

  -- cleanup (FK-ordnet)
  DELETE FROM conclusion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-2001);
  DELETE FROM citation WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-2001));
  DELETE FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-2001);
  DELETE FROM fact WHERE subjekt_type='person' AND subjekt_id=-2001;
  DELETE FROM family_member WHERE person_id IN (-2001,-2002,-2003,-2004,-2005) OR family_id IN (-3001,-3002,-3099);
  DELETE FROM family WHERE id IN (-3001,-3002,-3099);
  DELETE FROM person WHERE id IN (-2001,-2002,-2003,-2004,-2005);
  DELETE FROM source WHERE id IN (-9001,-9002);
  RAISE NOTICE 'OK: forældre-konflikt (selv-helende, idempotens, korroboration, konflikt→omstridt+konfidens, view, vælg+flyt+P1, skift-tilbage, forældre_ukendt-guard, 3 fakta-guards, 3 konklusions-dør-guards, tilfoej_barn-prætjek, rå EXCLUDE)';
END $$;

-- ===== Problem 2 — undo af adjudikation (fortryd genopretter BÅDE conclusion og barn-række) =====
-- Beviser at family_member ER versions-sporet (red_flyt_barn's flytning er undo-bar) og at fortryd-
-- replay ikke tripper EXCLUDE. Eget change_set pr. trin via app.change_set_id-reset (som Task 8).
DO $$
DECLARE v jsonb; a1 bigint; a2 bigint; v_slot bigint; cs bigint; v_fam bigint; v_valgt bigint; v_status text;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE NOTICE 'SPRINGER OVER forældre-undo: ikke redaktion'; RETURN; END IF;
  DELETE FROM conclusion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-2011);
  DELETE FROM citation WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-2011));
  DELETE FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-2011);
  DELETE FROM fact WHERE subjekt_type='person' AND subjekt_id=-2011;
  DELETE FROM family_member WHERE person_id IN (-2011,-2012,-2013,-2014,-2015) OR family_id IN (-3011,-3012);
  DELETE FROM family WHERE id IN (-3011,-3012); DELETE FROM person WHERE id IN (-2011,-2012,-2013,-2014,-2015);

  INSERT INTO person(id, levende, koen) VALUES (-2011,false,'mand'),(-2012,false,'mand'),(-2013,false,'kvinde'),(-2014,false,'mand'),(-2015,false,'kvinde');
  INSERT INTO family(id, type) VALUES (-3011,'vielse'),(-3012,'vielse');
  INSERT INTO family_member(family_id, person_id, rolle) VALUES
    (-3011,-2012,'partner'),(-3011,-2013,'partner'),(-3012,-2014,'partner'),(-3012,-2015,'partner'),(-3011,-2011,'barn');

  v := red_tilfoej_foraeldre_paastand(-2011,-3011); a1 := (v->>'assertion_id')::bigint; v_slot := (v->>'fact_id')::bigint;
  v := red_tilfoej_foraeldre_paastand(-2011,-3012); a2 := (v->>'assertion_id')::bigint;  -- konflikt

  -- adjudikér udgave 2 i EGET change_set → flytter barn -3011→-3012 + re-peg conclusion
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_vaelg_foraeldre(a2, 'sikker');
  SELECT max(id) INTO cs FROM change_set;
  IF (SELECT family_id FROM family_member WHERE person_id=-2011 AND rolle='barn') <> -3012 THEN RAISE EXCEPTION 'undo-setup: barn ikke flyttet'; END IF;

  -- fortryd → barn tilbage i -3011, conclusion tilbage til udgave 1 (a1), INGEN exclusion_violation under replay
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(cs, false);
  SELECT family_id INTO v_fam FROM family_member WHERE person_id=-2011 AND rolle='barn';
  IF v_fam <> -3011 THEN RAISE EXCEPTION 'undo: barn-række ikke genoprettet til -3011 (fik %)', v_fam; END IF;
  SELECT valgt_assertion_id, status INTO v_valgt, v_status FROM conclusion WHERE target_type='fact' AND target_id=v_slot;
  IF v_valgt <> a1 THEN RAISE EXCEPTION 'undo: conclusion ikke genoprettet til udgave 1 (valgt=%)', v_valgt; END IF;

  DELETE FROM conclusion WHERE target_type='fact' AND target_id=v_slot;
  DELETE FROM citation WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='fact' AND target_id=v_slot);
  DELETE FROM assertion WHERE target_type='fact' AND target_id=v_slot;
  DELETE FROM fact WHERE id=v_slot;
  DELETE FROM family_member WHERE person_id IN (-2011,-2012,-2013,-2014,-2015) OR family_id IN (-3011,-3012);
  DELETE FROM family WHERE id IN (-3011,-3012); DELETE FROM person WHERE id IN (-2011,-2012,-2013,-2014,-2015);
  RAISE NOTICE 'OK: forældre-undo (fortryd genoprettede barn-række + conclusion, ingen EXCLUDE-brud under replay)';
END $$;

-- ===== Problem 2 — slot-vedligehold på ALLE strukturelle mutatorer (review 30, B1+B2) =====
-- red_tilfoej_barn (nyt barn) opretter slot; red_slet_familie_link (fjern barn) retrakterer;
-- red_flyt_barn følger slottet — så P1/komplethed holder for alle skrive-veje (§2 "ALLE skrive-veje").
DO $$
DECLARE v_fam bigint; v_slot bigint; v_status text;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE NOTICE 'SPRINGER OVER mutator-slot-vedligehold: ikke redaktion'; RETURN; END IF;
  DELETE FROM conclusion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id IN (-6001,-6002));
  DELETE FROM citation WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id IN (-6001,-6002)));
  DELETE FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id IN (-6001,-6002));
  DELETE FROM fact WHERE subjekt_type='person' AND subjekt_id IN (-6001,-6002);
  DELETE FROM family_member WHERE person_id IN (-6001,-6002,-6003,-6004,-6005,-6006) OR family_id IN (-6101,-6102);
  DELETE FROM family WHERE id IN (-6101,-6102); DELETE FROM person WHERE id IN (-6001,-6002,-6003,-6004,-6005,-6006);
  INSERT INTO person(id,levende) VALUES (-6001,false),(-6002,false),(-6003,false),(-6004,false),(-6005,false),(-6006,false);
  INSERT INTO family(id,type) VALUES (-6101,'vielse'),(-6102,'vielse');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (-6101,-6003,'partner'),(-6101,-6004,'partner'),(-6102,-6005,'partner'),(-6102,-6006,'partner');

  -- (B2) genuint nyt barn via red_tilfoej_barn → slot oprettet afklaret→familien
  PERFORM red_tilfoej_barn(-6101,-6001);
  SELECT f.id INTO v_slot FROM fact f WHERE f.subjekt_type='person' AND f.subjekt_id=-6001 AND f.faktatype='forældrefamilie';
  IF v_slot IS NULL THEN RAISE EXCEPTION 'B2: nyt barn fik intet slot'; END IF;
  IF NOT EXISTS(SELECT 1 FROM conclusion c JOIN assertion a ON a.id=c.valgt_assertion_id
    WHERE c.target_type='fact' AND c.target_id=v_slot AND c.status='afklaret' AND a.objekt_id=-6101)
  THEN RAISE EXCEPTION 'B2: slot ikke afklaret→rette familie'; END IF;

  -- (flyt) strukturel red_flyt_barn → slot følger til -6102
  PERFORM red_flyt_barn(-6101,-6102,-6001);
  SELECT a.objekt_id INTO v_fam FROM conclusion c JOIN assertion a ON a.id=c.valgt_assertion_id
    WHERE c.target_type='fact' AND c.target_id=v_slot AND c.status='afklaret';
  IF v_fam <> -6102 THEN RAISE EXCEPTION 'flyt: slot fulgte ikke til til-familien (fik %)', v_fam; END IF;
  IF (SELECT family_id FROM family_member WHERE person_id=-6001 AND rolle='barn') <> -6102 THEN RAISE EXCEPTION 'flyt: barn-række ikke flyttet'; END IF;

  -- (B1) fjern barn-række via red_slet_familie_link → slot retrakteret (ikke forældreløst afklaret)
  PERFORM red_slet_familie_link(-6102,-6001,'barn');
  SELECT status INTO v_status FROM conclusion WHERE target_type='fact' AND target_id=v_slot;
  IF v_status <> 'tilbagetrukket' THEN RAISE EXCEPTION 'B1: slot ikke retrakteret efter barn-slet (status=%)', v_status; END IF;

  -- (Codex #1) delete→re-add: retrakteret slot genoprettes til afklaret (ikke slotløs)
  PERFORM red_tilfoej_barn(-6102,-6001);
  SELECT status INTO v_status FROM conclusion WHERE target_type='fact' AND target_id=v_slot;
  IF v_status <> 'afklaret' THEN RAISE EXCEPTION 'Codex #1: slot ikke genoprettet afklaret ved re-add (status=%)', v_status; END IF;
  IF EXISTS(SELECT 1 FROM family_member fm WHERE fm.rolle='barn' AND fm.person_id=-6001
    AND NOT EXISTS(SELECT 1 FROM fact f JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id AND c.status IN ('afklaret','omstridt')
                   WHERE f.subjekt_type='person' AND f.subjekt_id=fm.person_id AND f.faktatype='forældrefamilie'))
  THEN RAISE EXCEPTION 'Codex #1: slotløs barn-række efter re-add'; END IF;

  DELETE FROM conclusion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id IN (-6001,-6002));
  DELETE FROM citation WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id IN (-6001,-6002)));
  DELETE FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id IN (-6001,-6002));
  DELETE FROM fact WHERE subjekt_type='person' AND subjekt_id IN (-6001,-6002);
  DELETE FROM family_member WHERE person_id IN (-6001,-6002,-6003,-6004,-6005,-6006) OR family_id IN (-6101,-6102);
  DELETE FROM family WHERE id IN (-6101,-6102); DELETE FROM person WHERE id IN (-6001,-6002,-6003,-6004,-6005,-6006);
  RAISE NOTICE 'OK: mutator-slot-vedligehold (B2 tilføj→opret, flyt→følg, B1 slet→retrakter, delete→re-add→afklaret)';
END $$;

-- ===== Problem 2 — global backfill-komplethed + P1-drift-fanger =====
-- Gated: kun meningsfuld på en base hvor forældre-backfillen ER kørt (≥1 slot). På en ikke-backfyldt
-- base (fx frisk daa_test2) springes den over. Bemærk: dette verificerer STRUKTUR (slot+valgt+projektion);
-- citation-KILDE-korrekthed garanteres ved konstruktion af den rene single-edition-bed (§5), ikke her.
DO $$
DECLARE v_uden int; v_p1 int; v_multi int;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM fact WHERE subjekt_type='person' AND faktatype='forældrefamilie') THEN
    RAISE NOTICE 'SPRINGER OVER forældre-backfill-komplethed: ingen forældrefamilie-slots (backfill ikke kørt på denne base)';
    RETURN;
  END IF;
  -- (1) hver 'barn'-række har et slot med afklaret ELLER omstridt conclusion
  SELECT count(*) INTO v_uden FROM family_member fm WHERE fm.rolle='barn'
    AND NOT EXISTS(SELECT 1 FROM fact f JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
                   WHERE f.subjekt_type='person' AND f.subjekt_id=fm.person_id AND f.faktatype='forældrefamilie'
                     AND c.status IN ('afklaret','omstridt'));
  IF v_uden > 0 THEN RAISE EXCEPTION 'backfill-komplethed: % barn-række(r) uden afklaret/omstridt forældrefamilie-slot', v_uden; END IF;
  -- (2) P1: afklaret slot ⇒ valgt assertions objekt_id = personens 'barn'-rækkes family_id
  SELECT count(*) INTO v_p1 FROM conclusion c
    JOIN assertion a ON a.id=c.valgt_assertion_id
    JOIN fact f ON f.id=c.target_id AND c.target_type='fact' AND f.subjekt_type='person' AND f.faktatype='forældrefamilie'
    WHERE c.status='afklaret'
      AND a.objekt_id IS DISTINCT FROM (SELECT family_id FROM family_member WHERE person_id=f.subjekt_id AND rolle='barn');
  IF v_p1 > 0 THEN RAISE EXCEPTION 'P1-drift: % afklaret slot(s) hvor valgt familie ≠ projiceret barn-række', v_p1; END IF;
  -- (3) hver slot-assertion har objekt_type='family' + eksisterende familie
  IF EXISTS(SELECT 1 FROM assertion a JOIN fact f ON f.id=a.target_id AND a.target_type='fact'
            WHERE f.faktatype='forældrefamilie' AND (a.objekt_type IS DISTINCT FROM 'family'
              OR NOT EXISTS(SELECT 1 FROM family fa WHERE fa.id=a.objekt_id)))
  THEN RAISE EXCEPTION 'backfill: slot-assertion m. ugyldig/manglende familie-reference'; END IF;
  SELECT count(*) INTO v_multi FROM red_foraeldre_konflikt;
  RAISE NOTICE 'OK: forældre-backfill-komplethed + P1-drift (alle barn-rækker slot-dækket, projektion konsistent; % åbne konflikter i red_foraeldre_konflikt)', v_multi;
END $$;
SELECT set_config('request.jwt.claim.sub','', false);

-- ===== Sikkerheds-hærdning: interne _-helpers ikke anon-kaldbare (review 30/fable) =====
DO $$
DECLARE fn text; v_bad text := '';
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    '_delete_relation_evidence(bigint)','_version_upsert_row(text, jsonb)','_version_delete_row(text, jsonb)',
    '_row_pk(text, jsonb)','_version_pk_where(text, jsonb)','_version_current_row(text, jsonb)']
  LOOP
    IF has_function_privilege('anon', fn, 'EXECUTE') OR has_function_privilege('authenticated', fn, 'EXECUTE') THEN
      v_bad := v_bad || fn || ' ';
    END IF;
  END LOOP;
  IF v_bad <> '' THEN RAISE EXCEPTION 'Sikkerhed: anon/authenticated har EXECUTE på interne helper(e): %', v_bad; END IF;
  -- _delete_relation_evidence har DESUDEN en rolle-guard (belt-and-suspenders)
  BEGIN PERFORM set_config('request.jwt.claim.sub','',true); PERFORM _delete_relation_evidence(-999999);
    RAISE EXCEPTION 'Sikkerhed: _delete_relation_evidence-guard fyrede ikke';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%relations-slet-helper%' THEN RAISE; END IF; END;
  -- _regen_mentions_for er BEVIDST ikke revoked (SECURITY INVOKER-trigger kalder den som skriveren)
  RAISE NOTICE 'OK: interne _-helpers ikke anon-kaldbare (REVOKE + guard); _regen_mentions_for bevidst undtaget';
END $$;

-- ===== Dato-hærdning A1: additive felter (plan Spor A, 2026-07-17) =====
DO $$
DECLARE v_mangler text;
BEGIN
  DELETE FROM assertion WHERE id BETWEEN -987654326 AND -987654321;  -- ryd evt. residual fra fejlet kørsel
  -- (1) date_certainty-kolonne findes
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='assertion' AND column_name='date_certainty') THEN
    RAISE EXCEPTION 'A1: assertion.date_certainty-kolonne mangler'; END IF;
  -- (2) CHECK afviser ugyldig værdi
  BEGIN
    INSERT INTO assertion (id,target_type,target_id,date_certainty) VALUES (-987654321,'fact',-1,'sikker-forkert');
    RAISE EXCEPTION 'A1: date_certainty-CHECK fyrede ikke på ugyldig værdi';
  EXCEPTION WHEN check_violation THEN NULL;  -- forventet
  END;
  -- (3) gyldige værdier + NULL tillades
  INSERT INTO assertion (id,target_type,target_id,date_certainty) VALUES
    (-987654322,'fact',-1,'certain'),(-987654323,'fact',-1,'uncertain'),
    (-987654324,'fact',-1,'ambiguous'),(-987654325,'fact',-1,NULL);
  -- (4) calendar-DEFAULT anvendes når kolonnen udelades
  INSERT INTO assertion (id,target_type,target_id) VALUES (-987654326,'fact',-1);
  IF (SELECT calendar FROM assertion WHERE id=-987654326) IS DISTINCT FROM 'gregoriansk' THEN
    RAISE EXCEPTION 'A1: calendar-DEFAULT er ikke gregoriansk'; END IF;
  -- (5) faktavokabular seedet (kerne-dato-/event-typer)
  SELECT string_agg(w.code,' ') INTO v_mangler FROM (VALUES
    ('fødsel'),('dåb'),('død'),('begravelse'),('floruit'),('naturalisering'),('introduktion_ridderhus'))
    AS w(code) WHERE NOT EXISTS (SELECT 1 FROM vocab WHERE scheme='faktatype' AND vocab.code=w.code);
  IF v_mangler IS NOT NULL THEN RAISE EXCEPTION 'A1: faktatype-vokabular mangler: %', v_mangler; END IF;
  DELETE FROM assertion WHERE id BETWEEN -987654326 AND -987654321;  -- oprydning
  RAISE NOTICE 'OK: dato-hærdning A1 (date_certainty-kolonne+CHECK, calendar-default, faktavokabular)';
END $$;

-- ===== K2: staging-gate skjuler ny-udgave-poster for anon (plan Konvergens/K2, 2026-07-17) =====
DO $$
DECLARE vis_staged int; vis_ikke_staged int; vis_null_staged int;
BEGIN
  DELETE FROM person WHERE id BETWEEN -987655003 AND -987655001;  -- ryd residual
  -- afdød (levende=FALSE), ikke-privat: STAGED skal skjule, IKKE-staged skal vise
  INSERT INTO person (id, levende, privat, staged) VALUES
    (-987655001, false, false, true),    -- staged  → skjult
    (-987655002, false, false, false),   -- ikke-staged → synlig
    (-987655003, false, false, NULL);    -- NULL staged → synlig (fail-open-sikkert: kun loader sætter TRUE)
  IF person_offentlig(-987655001) THEN
    RAISE EXCEPTION 'K2: staged person er offentlig (skulle være skjult)'; END IF;
  IF NOT person_offentlig(-987655002) THEN
    RAISE EXCEPTION 'K2: ikke-staged afdød person er skjult (skulle være synlig)'; END IF;
  IF NOT person_offentlig(-987655003) THEN
    RAISE EXCEPTION 'K2: NULL-staged person er skjult (skulle være synlig — default)'; END IF;
  -- Test den FAKTISKE tabel-policy som anon, ikke kun hjælperen. Det fanger drift
  -- hvor person_offentlig er korrekt, men person.anon_read glemmer staged.
  SET LOCAL ROLE anon;
  SELECT count(*) INTO vis_staged FROM person WHERE id=-987655001;
  SELECT count(*) INTO vis_ikke_staged FROM person WHERE id=-987655002;
  SELECT count(*) INTO vis_null_staged FROM person WHERE id=-987655003;
  RESET ROLE;
  IF NOT (vis_staged=0 AND vis_ikke_staged=1 AND vis_null_staged=1) THEN
    RAISE EXCEPTION 'K2 person-RLS FEJL: staged=% (vent 0), ikke-staged=% (vent 1), NULL=% (vent 1)',
      vis_staged, vis_ikke_staged, vis_null_staged;
  END IF;
  DELETE FROM person WHERE id BETWEEN -987655003 AND -987655001;
  RAISE NOTICE 'OK: K2 staging-gate (hjælper + faktisk anon person-RLS)';
END $$;

-- ===== Levende feed fase 2: haendelse-skema, RLS, RPC og fortryd =====
DO $$
DECLARE
  v_live int; v_hidden int; v_private int; v_public int; v_auth_hidden int;
  v_uid uuid := '00000000-0000-0000-0000-0000000000f2';
  v_cs bigint; v_undo bigint; v_before jsonb; v_after jsonb; v_result jsonb;
BEGIN
  IF to_regclass('public.haendelse') IS NULL THEN
    RAISE EXCEPTION 'Fase2: haendelse-tabellen mangler';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM version_pk_registry WHERE tabel='haendelse') THEN
    RAISE EXCEPTION 'Fase2: haendelse mangler i version_pk_registry';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                 WHERE tgrelid='public.haendelse'::regclass AND tgname='trg_log_haendelse'
                   AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'Fase2: trg_log_haendelse mangler';
  END IF;

  DELETE FROM haendelse WHERE id BETWEEN -987656029 AND -987656020;
  DELETE FROM narrative WHERE id BETWEEN -987656019 AND -987656010;
  DELETE FROM person WHERE id IN (-987656001,-987656002);
  INSERT INTO person(id,levende,privat,staged) VALUES
    (-987656001,true,false,false),(-987656002,false,false,false);
  INSERT INTO narrative(id,subjekt_type,subjekt_id,tekst,privat) VALUES
    (-987656011,'person',-987656001,'Levende testnarrativ',false),
    (-987656012,'person',-987656002,'Offentligt testnarrativ',false),
    (-987656013,'person',-987656002,'Privat testnarrativ',true);
  INSERT INTO haendelse(id,subjekt_type,subjekt_id,narrative_id,noegle,klausul,feed_status) VALUES
    (-987656021,'person',-987656001,-987656011,'live','Levende hændelse','kandidat'),
    (-987656022,'person',-987656002,-987656012,'hidden','Skjult hændelse','skjult'),
    (-987656023,'person',-987656002,-987656013,'private','Privat hændelse','kandidat'),
    (-987656024,'person',-987656002,-987656012,'public','Offentlig hændelse','kandidat');
  BEGIN
    INSERT INTO haendelse(id,subjekt_type,subjekt_id,narrative_id,noegle,klausul,feed_status)
      VALUES (-987656025,'person',-987656002,-987656012,'invalid','Ugyldig','ingen');
    RAISE EXCEPTION 'Fase2: feed_status-CHECK fyrede ikke';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  SET LOCAL ROLE anon;
  SELECT count(*) INTO v_live FROM haendelse WHERE id=-987656021;
  SELECT count(*) INTO v_hidden FROM haendelse WHERE id=-987656022;
  SELECT count(*) INTO v_private FROM haendelse WHERE id=-987656023;
  SELECT count(*) INTO v_public FROM haendelse WHERE id=-987656024;
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_auth_hidden FROM haendelse WHERE id=-987656022;
  RESET ROLE;
  IF v_live<>0 OR v_hidden<>0 OR v_private<>0 OR v_public<>1 OR v_auth_hidden<>0 THEN
    RAISE EXCEPTION 'Fase2 RLS FEJL live=% hidden=% private=% public=% auth_hidden=%',
      v_live,v_hidden,v_private,v_public,v_auth_hidden;
  END IF;

  PERFORM set_config('request.jwt.claim.sub','',true);
  BEGIN
    PERFORM red_set_haendelse_status(-987656024,'interessant');
    RAISE EXCEPTION 'Fase2: ikke-redaktør blev ikke afvist';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE 'Kun redaktion%' THEN RAISE; END IF;
  END;

  INSERT INTO auth.users(id,email) VALUES (v_uid,'fase2@test.invalid') ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES (v_uid,'redaktion','fase2@test.invalid')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('request.jwt.claim.sub',v_uid::text,true);
  BEGIN
    PERFORM red_set_haendelse_status(-987656024,'ingen');
    RAISE EXCEPTION 'Fase2: ugyldig RPC-status blev ikke afvist';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%ikke en gyldig feed-status%' THEN RAISE; END IF;
  END;

  SELECT to_jsonb(h)-'feed_status' INTO v_before FROM haendelse h WHERE id=-987656024;
  PERFORM red_set_haendelse_status(-987656024,'interessant');
  v_cs := current_setting('app.change_set_id')::bigint;
  IF (SELECT feed_status FROM haendelse WHERE id=-987656024) <> 'interessant' THEN
    RAISE EXCEPTION 'Fase2: RPC satte ikke interessant';
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  -- red_set_haendelse_status opens its legacy change_set via max(id)+1.
  -- Synchronize the owned sequence before the undo writer's normal automatic
  -- INSERT so this fixture reaches its intended restoration assertions.
  PERFORM setval(
    pg_get_serial_sequence('public.change_set','id'),
    (SELECT coalesce(max(id),1) FROM public.change_set),
    true
  );
  v_result := red_fortryd_change_set(v_cs,false);
  v_undo := (v_result->>'reversal_change_set')::bigint;
  SELECT to_jsonb(h)-'feed_status' INTO v_after FROM haendelse h WHERE id=-987656024;
  IF (SELECT feed_status FROM haendelse WHERE id=-987656024) <> 'kandidat' OR v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'Fase2: fortryd genskabte ikke status/projektionskolonner';
  END IF;

  PERFORM set_config('app.change_set_id','',true);
  DELETE FROM haendelse WHERE id BETWEEN -987656029 AND -987656020;
  DELETE FROM narrative WHERE id BETWEEN -987656019 AND -987656010;
  DELETE FROM person WHERE id IN (-987656001,-987656002);
  DELETE FROM change_event WHERE change_set_id IN (v_cs,v_undo);
  DELETE FROM change_set WHERE id=v_undo;
  DELETE FROM change_set WHERE id=v_cs;
  DELETE FROM profiles WHERE id=v_uid;
  DELETE FROM auth.users WHERE id=v_uid;
  PERFORM set_config('request.jwt.claim.sub','',true);
  RAISE NOTICE 'OK: levende feed fase 2 (haendelse CHECK/RLS/RPC/versionering/fortryd)';
END $$;

-- ===== Mediehåndtering fase 1: metadata, genopret, upload-signatur og undo =====
DO $$
DECLARE v_id bigint; v_upload bigint; v_cs bigint; v_cs_foer int; v_cs_efter int;
        v_relation bigint; v_sha text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);

  INSERT INTO media(slags,titel,kunstner,datering,upload_status,maa_publiceres)
    VALUES ('foto','Gammel titel','Gammel kunstner','1699','klar',false)
    RETURNING id INTO v_id;

  SELECT count(*) INTO v_cs_foer FROM change_set;
  PERFORM red_opdater_media(v_id, 'Ny titel', NULL, '', 'ca. 1700');
  IF NOT EXISTS (SELECT 1 FROM media WHERE id=v_id AND titel='Ny titel' AND slags='foto'
                 AND kunstner IS NULL AND datering='ca. 1700') THEN
    RAISE EXCEPTION 'FEJL: red_opdater_media overholdt ikke NULL/tom-streng-kontrakten';
  END IF;
  SELECT count(*) INTO v_cs_efter FROM change_set;
  IF v_cs_efter <> v_cs_foer + 1 THEN
    RAISE EXCEPTION 'FEJL: red_opdater_media oprettede % change_set (vent 1)', v_cs_efter-v_cs_foer;
  END IF;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_opdater_media(v_id, NULL, '', NULL, NULL);
    RAISE EXCEPTION 'FEJL: tom slags blev accepteret';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Slags kan ikke ryddes%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_opdater_media(-999999999, 'Ukendt', NULL, NULL, NULL);
    RAISE EXCEPTION 'FEJL: ukendt media-id blev accepteret';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Media % findes ikke%' THEN RAISE; END IF;
  END;
  SELECT max(id) INTO v_cs FROM change_set;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(v_cs, false);
  IF NOT EXISTS (SELECT 1 FROM media WHERE id=v_id AND titel='Gammel titel' AND kunstner='Gammel kunstner') THEN
    RAISE EXCEPTION 'FEJL: undo af media-metadata gendannede ikke rækken';
  END IF;

  UPDATE media SET upload_status='fjernet' WHERE id=v_id;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_genopret_media(v_id);
  IF (SELECT upload_status FROM media WHERE id=v_id) <> 'klar' THEN
    RAISE EXCEPTION 'FEJL: red_genopret_media satte ikke klar';
  END IF;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_genopret_media(v_id);
    RAISE EXCEPTION 'FEJL: genopret-guard accepterede et ikke-fjernet medie';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Kan kun genoprette et fjernet medie%' THEN RAISE; END IF;
  END;

  PERFORM set_config('app.change_set_id','',true);
  v_sha := '__verify_fase3_sha_' || v_id;
  v_upload := red_upload_media(
    p_slags => 'foto', p_titel => 'Upload-test',
    p_storage_path => '__verify__/fase1-' || v_id || '.jpg', p_mime => 'image/jpeg',
    p_kunstner => 'Testkunstner', p_datering => '1701',
    p_sha256 => v_sha,
    p_rettigheder_status => 'ukendt', p_maa_publiceres => false
  );
  IF NOT EXISTS (SELECT 1 FROM media WHERE id=v_upload AND kunstner='Testkunstner' AND datering='1701'
                 AND sha256=v_sha AND created_at IS NOT NULL) THEN
    RAISE EXCEPTION 'FEJL: red_upload_media førte ikke metadata/sha256/created_at igennem';
  END IF;
  BEGIN
    PERFORM red_upload_media(
      p_slags => 'foto', p_titel => 'Upload-dublet-test',
      p_storage_path => '__verify__/fase1-dublet-' || v_id || '.jpg', p_mime => 'image/jpeg',
      p_sha256 => v_sha,
      p_rettigheder_status => 'ukendt', p_maa_publiceres => false
    );
    RAISE EXCEPTION 'FEJL: red_upload_media accepterede gentaget sha256';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Medie med samme indhold findes allerede (sha256=%' THEN RAISE; END IF;
  END;
  v_relation := red_relation('person',-999951,'media',v_upload,'afbildet');
  IF v_relation IS NULL OR NOT EXISTS (
    SELECT 1 FROM relation
    WHERE id=v_relation AND subjekt_type='person' AND subjekt_id=-999951
      AND objekt_type='media' AND objekt_id=v_upload AND rolle='afbildet'
  ) THEN
    RAISE EXCEPTION 'FEJL: første red_relation-kald returnerede/indsatte ikke relationen';
  END IF;
  BEGIN
    PERFORM red_relation('person',-999951,'media',v_upload,'afbildet');
    RAISE EXCEPTION 'FEJL: red_relation accepterede dublet-afbildet';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'Mediet er allerede tilknyttet dette subjekt' THEN RAISE; END IF;
  END;

  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: media fase 1 RPC + undo + upload-signatur (rullet tilbage)';
  ELSE RAISE; END IF;
END $$;

-- ===== Mediehåndtering fase 3: fremmed unique-constraint genkastes uændret =====
-- relation_pkey-racet kan ikke reproduceres deterministisk i én sekventiel session.
-- Simulér derfor PostgreSQL-diagnostikken og assert, at den brede handler ikke
-- maskerer den som en afbildet-dublet.
DO $$
DECLARE v_sqlstate text; v_constraint_name text; v_message text;
BEGIN
  BEGIN
    BEGIN
      RAISE EXCEPTION 'simuleret relation_pkey-kollision'
        USING ERRCODE='23505', CONSTRAINT='relation_pkey';
    EXCEPTION WHEN unique_violation THEN
      DECLARE v_constraint_name text;
      BEGIN
        GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
        IF v_constraint_name = 'relation_afbildet_uidx' THEN
          RAISE EXCEPTION 'Mediet er allerede tilknyttet dette subjekt';
        END IF;
        RAISE;
      END;
    END;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_sqlstate = RETURNED_SQLSTATE,
      v_constraint_name = CONSTRAINT_NAME,
      v_message = MESSAGE_TEXT;
  END;

  IF v_sqlstate IS DISTINCT FROM '23505'
     OR v_constraint_name IS DISTINCT FROM 'relation_pkey'
     OR v_message IS DISTINCT FROM 'simuleret relation_pkey-kollision' THEN
    RAISE EXCEPTION 'FEJL: fremmed unique-fejl blev ændret: sqlstate=%, constraint=%, message=%',
      v_sqlstate, v_constraint_name, v_message;
  END IF;
  RAISE NOTICE 'OK: fremmed unique-constraint genkastes uændret';
END $$;

-- ===== Mediehåndtering fase 4: red_erstat_media_fil (erstat fil, stabil identitet) =====
DO $$
DECLARE v_id bigint; v_rel bigint; v_andet bigint; v_cs bigint; v_thumb_foer text; v_thumb_efter text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);

  -- Seed: klart medie med sha + thumb-variant + afbildet-relation (identiteten der skal overleve)
  v_id := (SELECT coalesce(max(id),0)+1 FROM media);
  INSERT INTO media(id,slags,titel,storage_path,mime_type,byte_size,bredde,hoejde,sha256,
                    original_filnavn,upload_status,maa_publiceres)
    VALUES (v_id,'foto','Erstat-test','redaktor/aa/gammel-large.jpg','image/jpeg',100,20,10,
            '__f4_gammel_sha_'||v_id,'gammel.jpg','klar',false);
  INSERT INTO media_variant(id,media_id,tier,storage_path)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM media_variant),v_id,'thumb','redaktor/aa/gammel-thumb.jpg');
  v_rel := red_relation('person',-999941,'media',v_id,'afbildet');
  SELECT storage_path INTO v_thumb_foer FROM media_variant WHERE media_id=v_id AND tier='thumb';

  -- Happy path: én transaktion flytter identiteten + re-registrerer varianter
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_erstat_media_fil(v_id,'redaktor/bb/ny-large.jpg','image/jpeg',200,40,20,
    '__f4_ny_sha_'||v_id, NULL,
    jsonb_build_array(jsonb_build_object('tier','thumb','storage_path','redaktor/bb/ny-thumb.jpg',
      'mime','image/jpeg','byte_size',5,'bredde',4,'hoejde',2)));
  IF NOT EXISTS (SELECT 1 FROM media WHERE id=v_id AND storage_path='redaktor/bb/ny-large.jpg'
                 AND sha256='__f4_ny_sha_'||v_id AND byte_size=200
                 AND original_filnavn='gammel.jpg' AND upload_status='klar') THEN
    RAISE EXCEPTION 'FEJL: erstat opdaterede ikke rækken korrekt (eller mistede original_filnavn)';
  END IF;
  SELECT storage_path INTO v_thumb_efter FROM media_variant WHERE media_id=v_id AND tier='thumb';
  IF v_thumb_efter <> 'redaktor/bb/ny-thumb.jpg' THEN
    RAISE EXCEPTION 'FEJL: varianten blev ikke re-registreret atomisk';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM relation WHERE id=v_rel AND objekt_id=v_id) THEN
    RAISE EXCEPTION 'FEJL: relationen overlevede ikke erstatningen';
  END IF;

  -- Guard: identisk sha (no-op-erstat afvises)
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_erstat_media_fil(v_id,'redaktor/bb/ny-large.jpg','image/jpeg',200,40,20,'__f4_ny_sha_'||v_id);
    RAISE EXCEPTION 'FEJL: identisk sha blev accepteret';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Filen er identisk med den nuværende%' THEN RAISE; END IF;
  END;

  -- Guard: sha på ANDEN række (dedup-bagstopper)
  v_andet := (SELECT coalesce(max(id),0)+1 FROM media);
  INSERT INTO media(id,slags,upload_status,sha256) VALUES (v_andet,'foto','klar','__f4_andet_sha_'||v_id);
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_erstat_media_fil(v_id,'redaktor/cc/x.jpg','image/jpeg',1,1,1,'__f4_andet_sha_'||v_id);
    RAISE EXCEPTION 'FEJL: fremmed sha blev accepteret';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Medie med samme indhold findes allerede%' THEN RAISE; END IF;
  END;

  -- Guard: kun 'klar' (status='fjernet')
  UPDATE media SET upload_status='fjernet' WHERE id=v_id;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_erstat_media_fil(v_id,'redaktor/dd/y.jpg','image/jpeg',1,1,1,'__f4_tredje_sha_'||v_id);
    RAISE EXCEPTION 'FEJL: fjernet medie kunne erstattes';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Kan kun erstatte filen på et klart medie%' THEN RAISE; END IF;
  END;

  -- Guard: kun 'klar' (status='kladde') — dækker den anden ikke-'klar' status,
  -- ikke kun 'fjernet'
  UPDATE media SET upload_status='kladde' WHERE id=v_id;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_erstat_media_fil(v_id,'redaktor/dd/y.jpg','image/jpeg',1,1,1,'__f4_fjerde_sha_'||v_id);
    RAISE EXCEPTION 'FEJL: kladde-medie kunne erstattes';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Kan kun erstatte filen på et klart medie%' THEN RAISE; END IF;
  END;
  UPDATE media SET upload_status='klar' WHERE id=v_id;

  -- Guard: nonexistent media id
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_erstat_media_fil(-999999999,'redaktor/dd/y.jpg','image/jpeg',1,1,1,'__f4_femte_sha_'||v_id);
    RAISE EXCEPTION 'FEJL: ikke-eksisterende media blev accepteret';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Media % findes ikke%' THEN RAISE; END IF;
  END;

  -- Fortryd: media-rækken ruller tilbage til gamle stier; variant-rækken bliver
  -- BEVIDST stående på den nye sti (uversioneret cache, B8 — spec §3.2, plan-beslutning §10.3)
  SELECT max(id) INTO v_cs FROM change_set WHERE operation='red_erstat_media_fil';
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(v_cs, false);
  IF NOT EXISTS (SELECT 1 FROM media WHERE id=v_id AND storage_path='redaktor/aa/gammel-large.jpg'
                 AND sha256='__f4_gammel_sha_'||v_id) THEN
    RAISE EXCEPTION 'FEJL: fortryd rullede ikke media-rækken tilbage';
  END IF;
  IF (SELECT storage_path FROM media_variant WHERE media_id=v_id AND tier='thumb')
     <> 'redaktor/bb/ny-thumb.jpg' THEN
    RAISE EXCEPTION 'FEJL: variant-cache uventet versioneret (B8-kontrakten er brudt)';
  END IF;

  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: media fase 4 erstat-fil (guards, atomiske varianter, fortryd, rullet tilbage)';
  ELSE RAISE; END IF;
END $$;

-- ===== Mediehåndtering fase 4: red_udrens_media + preview (den rigtige sletning) =====
-- Review 34: seeder BEVIDST alle syv polymorfe ankre (relation, mention, fakta via LIVE
-- red_set_media_rettigheder, story via red_opret_story, narrativ via red_upsert_narrativ,
-- note direkte, forslag via LIVE red_suggest) og rydder dem én ad gangen — den oprindelige
-- plan seedede kun to og passerede grøn med H1/H3 til stede. H2 (atomisk guard+slet) er ikke
-- serielt testbar; den verificeres ved kode-form (ét DELETE-statement, Step 3) + race-
-- bagstopper-fejlteksten. Forslags-ankeret (Codex-review efter H1/H3) seedes via den RIGTIGE
-- red_suggest-RPC (ikke en hånd-rullet INSERT) — den kræver kun auth.uid() IS NOT NULL, ingen
-- rolle-check, så et almindeligt medlem (anden uid end redaktøren ovenfor) kan kalde den direkte.
DO $$
DECLARE v_id bigint; v_rel bigint; v_story bigint; v_narr bigint; v_note bigint; v_forslag bigint;
        v_prev jsonb; v_res jsonb; v_cs bigint;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);

  -- Seed: fjernet medie m. variant + ALLE syv ankre
  v_id := (SELECT coalesce(max(id),0)+1 FROM media);
  INSERT INTO media(id,slags,titel,storage_path,upload_status,maa_publiceres)
    VALUES (v_id,'foto','Udrens-test','redaktor/ee/udrens-large.jpg','fjernet',false);
  INSERT INTO media_variant(id,media_id,tier,storage_path)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM media_variant),v_id,'thumb','redaktor/ee/udrens-thumb.jpg');
  v_rel := red_relation('person',-999942,'media',v_id,'afbildet');
  INSERT INTO text_mention(kilde_type,kilde_id,maal_type,maal_id) VALUES ('narrative',-999942,'media',v_id);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_set_media_rettigheder(v_id,'afklaret',false,'CC-BY-4.0','Testarkivet',NULL,'fase4-verify');
  PERFORM set_config('app.change_set_id','',true);
  v_story := red_opret_story('media',v_id,'En story der peger direkte på mediet');
  PERFORM set_config('app.change_set_id','',true);
  v_narr := red_upsert_narrativ('media',v_id,'Et narrativ ophængt på mediet',false,NULL);
  v_note := (SELECT coalesce(max(id),0)+1 FROM note);
  INSERT INTO note(id,target_type,target_id,indhold) VALUES (v_note,'media',v_id,'defensiv note');
  IF NOT EXISTS (SELECT 1 FROM fact WHERE subjekt_type='media' AND subjekt_id=v_id) THEN
    RAISE EXCEPTION 'FEJL: seed-forudsætning brast — red_set_media_rettigheder skrev ingen fakta';
  END IF;
  -- Forslag via LIVE red_suggest, som en anden (ikke-redaktion) logget-ind bruger.
  INSERT INTO auth.users(id,email) VALUES
    ('00000000-0000-0000-0000-000000000002','media-fase4-medlem@test.invalid') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
  v_forslag := red_suggest('fakta','media',v_id,'titel','Foreslået ny titel');
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);

  -- Preview: blokeret af alle syv kategorier, med tællinger + stier
  v_prev := red_udrens_media_preview(v_id);
  IF (v_prev->>'kan_udrenses')::boolean
     OR (v_prev->>'antal_tilknytninger')::int <> 1
     OR (v_prev->>'antal_mentions')::int <> 1
     OR (v_prev->>'antal_fakta')::int <> 2          -- licens + kildehenvisning (tredje felt NULL)
     OR (v_prev->>'antal_stories')::int <> 1
     OR (v_prev->>'antal_narrativer')::int <> 1
     OR (v_prev->>'antal_noter')::int <> 1
     OR (v_prev->>'antal_forslag')::int <> 1
     OR jsonb_array_length(v_prev->'stier') <> 2
     OR jsonb_array_length(v_prev->'blokeringer') <> 7 THEN
    RAISE EXCEPTION 'FEJL: preview-blokeringer/tællinger forkerte: %', v_prev;
  END IF;

  -- Udrens blokeret af relation
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_udrens_media(v_id);
    RAISE EXCEPTION 'FEJL: udrens accepterede medie med relation';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Mediet har tilknytninger%' THEN RAISE; END IF;
  END;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_slet_relation(v_rel);

  -- Udrens blokeret af mention
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_udrens_media(v_id);
    RAISE EXCEPTION 'FEJL: udrens accepterede medie med mention';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Mediet er nævnt i narrativer%' THEN RAISE; END IF;
  END;
  DELETE FROM text_mention WHERE maal_type='media' AND maal_id=v_id;

  -- Udrens blokeret af rettigheds-fakta (H1) — preview skal også være rød med rette tekst
  v_prev := red_udrens_media_preview(v_id);
  IF (v_prev->>'kan_udrenses')::boolean
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(v_prev->'blokeringer') b
                    WHERE b LIKE '%rettighedsdokumentation%') THEN
    RAISE EXCEPTION 'FEJL: preview grøn/uklar trods rettigheds-fakta: %', v_prev;
  END IF;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_udrens_media(v_id);
    RAISE EXCEPTION 'FEJL: udrens accepterede medie med rettigheds-fakta (H1)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Mediet har rettighedsdokumentation%' THEN RAISE; END IF;
  END;
  -- Ryd fakta-blokeringen: HELE evidenskæden i FK-orden (red_slet_person-mønsteret, schema.sql:1128-1165)
  DELETE FROM citation WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='fact'
    AND target_id IN (SELECT id FROM fact WHERE subjekt_type='media' AND subjekt_id=v_id));
  DELETE FROM conclusion WHERE target_type='fact'
    AND target_id IN (SELECT id FROM fact WHERE subjekt_type='media' AND subjekt_id=v_id);
  DELETE FROM assertion WHERE target_type='fact'
    AND target_id IN (SELECT id FROM fact WHERE subjekt_type='media' AND subjekt_id=v_id);
  DELETE FROM note WHERE target_type='fact'
    AND target_id IN (SELECT id FROM fact WHERE subjekt_type='media' AND subjekt_id=v_id);
  DELETE FROM fact WHERE subjekt_type='media' AND subjekt_id=v_id;

  -- Udrens blokeret af story (H3)
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_udrens_media(v_id);
    RAISE EXCEPTION 'FEJL: udrens accepterede medie med story (H3)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Mediet er subjekt for en story%' THEN RAISE; END IF;
  END;
  DELETE FROM story WHERE id=v_story;

  -- Udrens blokeret af narrativ (H3) — evt. haendelser ville cascade FRA narrativet, ingen egen oprydning
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_udrens_media(v_id);
    RAISE EXCEPTION 'FEJL: udrens accepterede medie med narrativ (H3)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Mediet har et tilknyttet narrativ%' THEN RAISE; END IF;
  END;
  DELETE FROM narrative WHERE id=v_narr;

  -- Udrens blokeret af note (defensiv guard)
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_udrens_media(v_id);
    RAISE EXCEPTION 'FEJL: udrens accepterede medie med note (defensiv guard)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Mediet har noter%' THEN RAISE; END IF;
  END;
  DELETE FROM note WHERE id=v_note;

  -- Udrens blokeret af forslag i kø (Codex-review efter H1/H3 — suggestion som 7. anker)
  v_prev := red_udrens_media_preview(v_id);
  IF (v_prev->>'kan_udrenses')::boolean
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(v_prev->'blokeringer') b
                    WHERE b LIKE '%forslag i kø%') THEN
    RAISE EXCEPTION 'FEJL: preview grøn/uklar trods forslag i kø: %', v_prev;
  END IF;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_udrens_media(v_id);
    RAISE EXCEPTION 'FEJL: udrens accepterede medie med forslag i kø';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Mediet har forslag i kø%' THEN RAISE; END IF;
  END;
  DELETE FROM suggestion WHERE id=v_forslag;  -- ingen retract-RPC findes; direkte SQL er OK til test-oprydning

  -- Kun-fra-fjernet
  UPDATE media SET upload_status='klar' WHERE id=v_id;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_udrens_media(v_id);
    RAISE EXCEPTION 'FEJL: udrens accepterede et klart medie';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Kan kun udrense et fjernet medie%' THEN RAISE; END IF;
  END;
  UPDATE media SET upload_status='fjernet' WHERE id=v_id;

  -- Preview↔udrens-paritet på stier + selve sletningen
  v_prev := red_udrens_media_preview(v_id);
  IF NOT (v_prev->>'kan_udrenses')::boolean THEN RAISE EXCEPTION 'FEJL: preview burde være grøn nu: %', v_prev; END IF;
  PERFORM set_config('app.change_set_id','',true);
  v_res := red_udrens_media(v_id);
  IF jsonb_array_length(v_res->'stier') <> jsonb_array_length(v_prev->'stier') THEN
    RAISE EXCEPTION 'FEJL: preview og udrens er uenige om stierne (% vs %)', v_prev->'stier', v_res->'stier';
  END IF;
  IF EXISTS (SELECT 1 FROM media WHERE id=v_id) OR EXISTS (SELECT 1 FROM media_variant WHERE media_id=v_id) THEN
    RAISE EXCEPTION 'FEJL: række/varianter overlevede udrensningen';
  END IF;
  -- Intet forældreløst tilbage: fact-kæden, story, narrativ, note og forslag blev ryddet FØR
  -- udrens (blokerings-modellen), og efter udrens må INTET pege på det slettede medie (H1-garantien)
  IF EXISTS (SELECT 1 FROM fact WHERE subjekt_type='media' AND subjekt_id=v_id)
     OR EXISTS (SELECT 1 FROM story WHERE subjekt_type='media' AND subjekt_id=v_id)
     OR EXISTS (SELECT 1 FROM narrative WHERE subjekt_type='media' AND subjekt_id=v_id)
     OR EXISTS (SELECT 1 FROM note WHERE target_type='media' AND target_id=v_id)
     OR EXISTS (SELECT 1 FROM text_mention WHERE maal_type='media' AND maal_id=v_id)
     OR EXISTS (SELECT 1 FROM suggestion WHERE subjekt_type='media' AND subjekt_id=v_id) THEN
    RAISE EXCEPTION 'FEJL: forældreløst anker/evidens peger stadig på det udrensede medie';
  END IF;
  -- DELETE-event med foer-snapshot logget
  SELECT max(cs.id) INTO v_cs FROM change_set cs WHERE cs.operation='red_udrens_media';
  IF NOT EXISTS (SELECT 1 FROM change_event WHERE change_set_id=v_cs AND tabel='media'
                 AND op='DELETE' AND foer->>'id' = v_id::text AND efter IS NULL) THEN
    RAISE EXCEPTION 'FEJL: udrens loggede ikke DELETE med foer-snapshot';
  END IF;
  -- Fortryd genskaber rækken fra snapshottet — men uden varianter (dokumenteret hazard, spec §4.2)
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(v_cs, false);
  IF NOT EXISTS (SELECT 1 FROM media WHERE id=v_id AND upload_status='fjernet') THEN
    RAISE EXCEPTION 'FEJL: fortryd genskabte ikke media-rækken';
  END IF;
  IF EXISTS (SELECT 1 FROM media_variant WHERE media_id=v_id) THEN
    RAISE EXCEPTION 'FEJL: variant-rækker uventet genskabt (cache er ikke versioneret)';
  END IF;

  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: media fase 4 udrens (alle syv anker-guards, paritet, DELETE-log, fortryd uden varianter, rullet tilbage)';
  ELSE RAISE; END IF;
END $$;

-- ===== Mediehåndtering fase 4: relation.kvalifikator + red_saet_portraet =====
DO $$
DECLARE v_m1 bigint; v_m2 bigint; v_r1 bigint; v_r2 bigint;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);

  -- Kolonnen findes og er jsonb
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='relation'
                   AND column_name='kvalifikator' AND data_type='jsonb') THEN
    RAISE EXCEPTION 'FEJL: relation.kvalifikator mangler eller har forkert type';
  END IF;

  v_m1 := (SELECT coalesce(max(id),0)+1 FROM media);
  INSERT INTO media(id,slags,upload_status) VALUES (v_m1,'foto','klar');
  v_m2 := v_m1 + 1;
  INSERT INTO media(id,slags,upload_status) VALUES (v_m2,'foto','klar');
  v_r1 := red_relation('person',-999943,'media',v_m1,'afbildet');
  v_r2 := red_relation('person',-999943,'media',v_m2,'afbildet');

  -- Sæt portræt på m1
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_saet_portraet(-999943, v_m1);
  IF (SELECT kvalifikator->>'primaer' FROM relation WHERE id=v_r1) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'FEJL: primaer-flag blev ikke sat';
  END IF;

  -- Skift til m2 → søskende-nulstilling af m1
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_saet_portraet(-999943, v_m2);
  IF (SELECT kvalifikator FROM relation WHERE id=v_r1) IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: søskende-nulstilling efterlod kvalifikator på m1 (%)',
      (SELECT kvalifikator FROM relation WHERE id=v_r1);
  END IF;
  IF (SELECT kvalifikator->>'primaer' FROM relation WHERE id=v_r2) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'FEJL: flaget flyttede ikke til m2';
  END IF;

  -- Ryd-grenen (p_media_id = NULL)
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_saet_portraet(-999943, NULL);
  IF EXISTS (SELECT 1 FROM relation
             WHERE subjekt_type='person' AND subjekt_id=-999943 AND kvalifikator ? 'primaer') THEN
    RAISE EXCEPTION 'FEJL: ryd-grenen fjernede ikke flaget';
  END IF;

  -- Manglende relation → domæne-fejl, INGEN implicit oprettelse
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_saet_portraet(-999943, -424242);
    RAISE EXCEPTION 'FEJL: portræt accepteret uden relation';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Mediet er ikke tilknyttet personen%' THEN RAISE; END IF;
  END;

  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: media fase 4 portræt (kolonne, søskende-nulstilling, ryd, guard, rullet tilbage)';
  ELSE RAISE; END IF;
END $$;

-- ===== Levende feed fase 3: story/story_kilde/feed_pin — skema, RLS, RPC'er og fortryd =====
DO $$
DECLARE
  v_pub int; v_kladde int; v_levende int; v_privat int;
  v_kilde int; v_kilde_kladde int; v_pin int; v_auth_pub int; v_auth_kladde int;
  v_uid uuid := '00000000-0000-0000-0000-0000000000f3';
  v_seed_af uuid := '00000000-0000-0000-0000-0000000000f4';
  v_story bigint; v_cs_opret bigint; v_cs_status bigint;
  v_undo1 bigint; v_undo2 bigint; v_res jsonb;
BEGIN
  IF to_regclass('public.story') IS NULL THEN RAISE EXCEPTION 'Fase3: story-tabellen mangler'; END IF;
  IF to_regclass('public.story_kilde') IS NULL THEN RAISE EXCEPTION 'Fase3: story_kilde mangler'; END IF;
  IF to_regclass('public.feed_pin') IS NULL THEN RAISE EXCEPTION 'Fase3: feed_pin mangler'; END IF;
  IF NOT EXISTS (SELECT 1 FROM version_pk_registry WHERE tabel='story' AND skip_cols='{}') THEN
    RAISE EXCEPTION 'Fase3: story mangler i version_pk_registry uden skip_cols (fuld versionering, §3.7)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM version_pk_registry WHERE tabel='feed_pin' AND skip_cols='{}') THEN
    RAISE EXCEPTION 'Fase3: feed_pin mangler i version_pk_registry uden skip_cols';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.story'::regclass
                 AND tgname='trg_log_story' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'Fase3: trg_log_story mangler';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.feed_pin'::regclass
                 AND tgname='trg_log_feed_pin' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'Fase3: trg_log_feed_pin mangler';
  END IF;

  -- Oprydning + seeds
  DELETE FROM feed_pin WHERE kort_noegle LIKE 'verify3:%';
  DELETE FROM story_kilde WHERE id BETWEEN -987657029 AND -987657020;
  DELETE FROM story WHERE id BETWEEN -987657019 AND -987657010;
  DELETE FROM source WHERE id=-987657031;
  DELETE FROM person WHERE id IN (-987657001,-987657002);
  INSERT INTO person(id,levende,privat,staged) VALUES
    (-987657001,true,false,false),(-987657002,false,false,false);
  INSERT INTO source(id,titel,udgave) VALUES (-987657031,'Verify-kilde','1939');
  INSERT INTO story(id,subjekt_type,subjekt_id,tekst,status,privat,skabt_af) VALUES
    (-987657011,'person',-987657002,'Publiceret offentlig historie','publiceret',false,v_seed_af),
    (-987657012,'person',-987657002,'Kladde-historie','kladde',false,v_seed_af),
    (-987657013,'person',-987657001,'Publiceret om levende','publiceret',false,v_seed_af),
    (-987657014,'person',-987657002,'Publiceret men privat','publiceret',true,v_seed_af);
  INSERT INTO story_kilde(id,story_id,source_id,side) VALUES
    (-987657021,-987657011,-987657031,'112'),
    (-987657022,-987657012,-987657031,'7');
  INSERT INTO feed_pin(id,kort_noegle,handling,oprettet_af) VALUES
    (-987657041,'verify3:portrait:1','pin',v_seed_af);

  -- CHECK + UNIQUE
  BEGIN
    INSERT INTO story(id,subjekt_type,subjekt_id,tekst,status,skabt_af)
      VALUES (-987657015,'person',-987657002,'X','udgivet',v_seed_af);
    RAISE EXCEPTION 'Fase3: story.status-CHECK fyrede ikke';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO story(id,subjekt_type,subjekt_id,tekst,oprindelse,skabt_af)
      VALUES (-987657015,'person',-987657002,'X','ai',v_seed_af);
    RAISE EXCEPTION 'Fase3: story.oprindelse-CHECK fyrede ikke';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO feed_pin(id,kort_noegle,handling,oprettet_af)
      VALUES (-987657042,'verify3:x','fremhaev',v_seed_af);
    RAISE EXCEPTION 'Fase3: feed_pin.handling-CHECK fyrede ikke';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO feed_pin(id,kort_noegle,handling,oprettet_af)
      VALUES (-987657043,'verify3:portrait:1','skjul',v_seed_af);
    RAISE EXCEPTION 'Fase3: feed_pin UNIQUE(kort_noegle) fyrede ikke';
  EXCEPTION WHEN unique_violation THEN NULL; END;

  -- RLS-synlighed (anon + authenticated, F-02-linjen)
  SET LOCAL ROLE anon;
  SELECT count(*) INTO v_pub     FROM story WHERE id=-987657011;
  SELECT count(*) INTO v_kladde  FROM story WHERE id=-987657012;
  SELECT count(*) INTO v_levende FROM story WHERE id=-987657013;
  SELECT count(*) INTO v_privat  FROM story WHERE id=-987657014;
  SELECT count(*) INTO v_kilde        FROM story_kilde WHERE id=-987657021;
  SELECT count(*) INTO v_kilde_kladde FROM story_kilde WHERE id=-987657022;
  SELECT count(*) INTO v_pin FROM feed_pin WHERE kort_noegle='verify3:portrait:1';
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_auth_pub    FROM story WHERE id=-987657011;
  SELECT count(*) INTO v_auth_kladde FROM story WHERE id=-987657012;
  RESET ROLE;
  IF v_pub<>1 OR v_kladde<>0 OR v_levende<>0 OR v_privat<>0
     OR v_kilde<>1 OR v_kilde_kladde<>0 OR v_pin<>1
     OR v_auth_pub<>1 OR v_auth_kladde<>0 THEN
    RAISE EXCEPTION 'Fase3 RLS FEJL pub=% kladde=% levende=% privat=% kilde=% kilde_kladde=% pin=% auth_pub=% auth_kladde=%',
      v_pub,v_kladde,v_levende,v_privat,v_kilde,v_kilde_kladde,v_pin,v_auth_pub,v_auth_kladde;
  END IF;

  -- RPC-gates
  PERFORM set_config('request.jwt.claim.sub','',true);
  BEGIN
    PERFORM red_opret_story('person',-987657002,'Uautoriseret');
    RAISE EXCEPTION 'Fase3: red_opret_story afviste ikke ikke-redaktør';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'Kun redaktion%' THEN RAISE; END IF; END;
  BEGIN
    PERFORM red_set_feed_pin('verify3:portrait:1','pin');
    RAISE EXCEPTION 'Fase3: red_set_feed_pin afviste ikke ikke-redaktør';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'Kun redaktion%' THEN RAISE; END IF; END;

  INSERT INTO auth.users(id,email) VALUES (v_uid,'fase3@test.invalid') ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES (v_uid,'redaktion','fase3@test.invalid')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('request.jwt.claim.sub',v_uid::text,true);
  BEGIN
    PERFORM red_set_story_status(-987657011,'udgivet');
    RAISE EXCEPTION 'Fase3: ugyldig story-status blev ikke afvist';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%ikke en gyldig story-status%' THEN RAISE; END IF; END;
  BEGIN
    PERFORM red_set_feed_pin('verify3:x','fremhaev');
    RAISE EXCEPTION 'Fase3: ugyldig pin-handling blev ikke afvist';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%ikke en gyldig pin-handling%' THEN RAISE; END IF; END;

  -- Fortryd-assert (fuld versionering, §3.7/§3.8): begge retninger
  v_story := red_opret_story('person',-987657002,'Fortryd-testhistorie','Titel');
  v_cs_opret := current_setting('app.change_set_id')::bigint;
  PERFORM set_config('app.change_set_id','',true);
  BEGIN
    PERFORM red_set_story_status(v_story,'publiceret');
    RAISE EXCEPTION 'Fase3: publicering uden kilde blev accepteret';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE 'Story % kan ikke publiceres uden mindst én kilde' THEN RAISE; END IF;
  END;
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO story_kilde(id,story_id,source_id,side)
    VALUES (-987657023,v_story,-987657031,'112');
  PERFORM red_set_story_status(v_story,'publiceret');
  v_cs_status := current_setting('app.change_set_id')::bigint;
  IF (SELECT status FROM story WHERE id=v_story) <> 'publiceret'
     OR (SELECT publiceret_dato FROM story WHERE id=v_story) IS NULL THEN
    RAISE EXCEPTION 'Fase3: publicering satte ikke status/publiceret_dato';
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  v_res := red_fortryd_change_set(v_cs_status,false);
  v_undo1 := (v_res->>'reversal_change_set')::bigint;
  IF (SELECT status FROM story WHERE id=v_story) <> 'kladde' THEN
    RAISE EXCEPTION 'Fase3: fortryd af status-skiftet genskabte ikke kladde';
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  v_res := red_fortryd_change_set(v_cs_opret,false);
  v_undo2 := (v_res->>'reversal_change_set')::bigint;
  IF EXISTS (SELECT 1 FROM story WHERE id=v_story) THEN
    RAISE EXCEPTION 'Fase3: fortryd af opret-settet slettede ikke storyen';
  END IF;

  -- Oprydning
  PERFORM set_config('app.change_set_id','',true);
  DELETE FROM feed_pin WHERE kort_noegle LIKE 'verify3:%';
  DELETE FROM story_kilde WHERE id BETWEEN -987657029 AND -987657020;
  DELETE FROM story WHERE id BETWEEN -987657019 AND -987657010;
  DELETE FROM source WHERE id=-987657031;
  DELETE FROM person WHERE id IN (-987657001,-987657002);
  DELETE FROM change_event WHERE change_set_id IN (v_cs_opret,v_cs_status,v_undo1,v_undo2);
  DELETE FROM change_set WHERE id IN (v_undo1,v_undo2,v_cs_status,v_cs_opret);
  DELETE FROM profiles WHERE id=v_uid;
  DELETE FROM auth.users WHERE id=v_uid;
  PERFORM set_config('request.jwt.claim.sub','',true);
  RAISE NOTICE 'OK: levende feed fase 3 (story/story_kilde/feed_pin CHECK/UNIQUE/RLS/RPC/fuld versionering/fortryd)';
END $$;

-- Præsensliste: vokabular-seed for overhoved-faktatypen
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM vocab WHERE scheme='faktatype' AND code='overhoved') THEN
    RAISE EXCEPTION 'FEJL: vocab mangler (faktatype, overhoved) — kør db-migrations.sql';
  END IF;
END $$;

-- ===== Person OCR kvalitetsark — identitet =====
-- Selvstændig, rollback-sikker kontrakt for stabile importnøgler og den varige
-- korrektionsjournal. Den bruger rigtige constraints, trigger og SET ROLE, ikke
-- kildekode-matching, og efterlader derfor ingen verify-rækker.
DO $$
DECLARE
  v_kolonner int;
  v_redaktor uuid := '00000000-0000-0000-0000-0000000000c1';
  v_journal_id bigint;
  v_change_set bigint := -987658099;
  v_anon_blokeret boolean := false;
  v_indsaet_blokeret boolean := false;
  v_opdater_blokeret boolean := false;
  v_slet_blokeret boolean := false;
  v_medlem_antal int;
  v_redaktor_antal int;
BEGIN
  -- Eksakte kolonnekontrakter: nullable import-/record-nøgler bevarer legacy-rækker;
  -- journalens beslutningsfelter er obligatoriske bortset fra rettelse og aktør.
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='source'
                   AND column_name='import_key' AND data_type='text' AND is_nullable='YES') THEN
    RAISE EXCEPTION 'FEJL: source.import_key mangler eller har forkert type/nullability';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='person_external_id'
                   AND column_name='record_key' AND data_type='text' AND is_nullable='YES') THEN
    RAISE EXCEPTION 'FEJL: person_external_id.record_key mangler eller har forkert type/nullability';
  END IF;
  SELECT count(*) INTO v_kolonner
    FROM information_schema.columns
   WHERE table_schema='public' AND table_name='import_korrektion'
     AND ((column_name='id' AND data_type='bigint' AND is_nullable='NO')
       OR (column_name IN ('import_key','record_key','felt','input_fingerprint','status')
           AND data_type='text' AND is_nullable='NO')
       OR (column_name='importeret' AND data_type='jsonb' AND is_nullable='NO')
       OR (column_name='korrigeret' AND data_type='jsonb' AND is_nullable='YES')
       OR (column_name='actor_id' AND data_type='uuid' AND is_nullable='YES')
       OR (column_name='actor_navn' AND data_type='text' AND is_nullable='YES')
       OR (column_name IN ('oprettet_at','opdateret_at')
           AND data_type='timestamp with time zone' AND is_nullable='NO'));
  IF v_kolonner <> 12 THEN
    RAISE EXCEPTION 'FEJL: import_korrektion mangler eksakte kolonnekontrakter (fik %/12)', v_kolonner;
  END IF;

  -- Delvise unikke nøgler: ikke-NULL importidentiteter må aldrig dubleres,
  -- men de historiske NULL-rækker skal fortsat kunne sameksistere.
  INSERT INTO source(id,titel,import_key) VALUES
    (-987658001,'Legacy A',NULL),(-987658002,'Legacy B',NULL),
    (-987658003,'Import-nøgle','verify:ocr:source');
  BEGIN
    INSERT INTO source(id,titel,import_key) VALUES (-987658004,'Dublet','verify:ocr:source');
    RAISE EXCEPTION 'FEJL: source import_key-unikhed afviste ikke dublet';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  INSERT INTO person(id) VALUES (-987658011),(-987658012),(-987658013),(-987658014);
  INSERT INTO person_external_id(person_id,source_id,record_key) VALUES
    (-987658011,-987658003,NULL),(-987658012,-987658003,NULL),
    (-987658013,-987658003,'verify:ocr:record');
  BEGIN
    INSERT INTO person_external_id(person_id,source_id,record_key)
      VALUES (-987658014,-987658003,'verify:ocr:record');
    RAISE EXCEPTION 'FEJL: person_external_id record_key-unikhed afviste ikke dublet';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Journalens kontrollerede vokabular og MD5-fingerprint afviser ukendte værdier.
  BEGIN
    INSERT INTO import_korrektion(import_key,record_key,felt,input_fingerprint,importeret,status)
      VALUES ('verify:ocr','ukendt-felt','ukendt','0123456789abcdef0123456789abcdef','{}','aaben');
    RAISE EXCEPTION 'FEJL: import_korrektion.felt-CHECK afviste ikke ukendt felt';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO import_korrektion(import_key,record_key,felt,input_fingerprint,importeret,status)
      VALUES ('verify:ocr','ukendt-status','navn','0123456789abcdef0123456789abcdef','{}','ukendt');
    RAISE EXCEPTION 'FEJL: import_korrektion.status-CHECK afviste ikke ukendt status';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO import_korrektion(import_key,record_key,felt,input_fingerprint,importeret,status)
      VALUES ('verify:ocr','forkert-hash','navn','IKKE-EN-MD5','{}','aaben');
    RAISE EXCEPTION 'FEJL: import_korrektion.input_fingerprint-CHECK afviste ikke ugyldig hash';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM pg_constraint
             WHERE conrelid='public.import_korrektion'::regclass AND contype='f') THEN
    RAISE EXCEPTION 'FEJL: import_korrektion har FK til regenererbare identifikatorer';
  END IF;

  -- Registry + konkret trigger bevarer den immutable historik i change_event.
  IF NOT EXISTS (SELECT 1 FROM version_pk_registry
                 WHERE tabel='import_korrektion' AND pk_cols=ARRAY['id']::text[] AND skip_cols='{}') THEN
    RAISE EXCEPTION 'FEJL: import_korrektion mangler korrekt version_pk_registry-række';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                 WHERE tgrelid='public.import_korrektion'::regclass
                   AND tgname='trg_log_import_korrektion' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'FEJL: trg_log_import_korrektion mangler';
  END IF;

  INSERT INTO import_korrektion(import_key,record_key,felt,input_fingerprint,importeret,status)
    VALUES ('verify:ocr','journal','navn','0123456789abcdef0123456789abcdef','{"navn":"OCR"}','aaben')
    RETURNING id INTO v_journal_id;

  -- RLS og grants: anon har ingen adgang; medlemmet får ingen rækker; redaktøren
  -- må læse, men alle direkte DML-veje er lukkede indtil den kommende RPC.
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM 1 FROM import_korrektion WHERE id=v_journal_id;
  EXCEPTION WHEN insufficient_privilege THEN v_anon_blokeret := true;
  END;
  RESET ROLE;

  PERFORM set_config('request.jwt.claim.sub','',true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_medlem_antal FROM import_korrektion WHERE id=v_journal_id;
  RESET ROLE;

  INSERT INTO auth.users(id,email) VALUES (v_redaktor,'ocr-journal-verify@test.invalid');
  INSERT INTO profiles(id,rolle,email) VALUES (v_redaktor,'redaktion','ocr-journal-verify@test.invalid');
  PERFORM set_config('request.jwt.claim.sub',v_redaktor::text,true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_redaktor_antal FROM import_korrektion WHERE id=v_journal_id;
  BEGIN
    INSERT INTO import_korrektion(import_key,record_key,felt,input_fingerprint,importeret,status)
      VALUES ('verify:ocr','redaktor-indsaet','navn','0123456789abcdef0123456789abcdef','{}','aaben');
  EXCEPTION WHEN insufficient_privilege THEN v_indsaet_blokeret := true;
  END;
  BEGIN
    UPDATE import_korrektion SET actor_navn='må ikke ske' WHERE id=v_journal_id;
  EXCEPTION WHEN insufficient_privilege THEN v_opdater_blokeret := true;
  END;
  BEGIN
    DELETE FROM import_korrektion WHERE id=v_journal_id;
  EXCEPTION WHEN insufficient_privilege THEN v_slet_blokeret := true;
  END;
  RESET ROLE;
  IF NOT v_anon_blokeret OR v_medlem_antal <> 0 OR v_redaktor_antal <> 1
     OR NOT v_indsaet_blokeret OR NOT v_opdater_blokeret OR NOT v_slet_blokeret THEN
    RAISE EXCEPTION 'FEJL: journal-RLS/grants anon=% medlem=% redaktor=% dml=%/%/%',
      v_anon_blokeret,v_medlem_antal,v_redaktor_antal,
      v_indsaet_blokeret,v_opdater_blokeret,v_slet_blokeret;
  END IF;

  INSERT INTO change_set(id,operation) VALUES (v_change_set,'verify_import_korrektion');
  PERFORM set_config('app.change_set_id',v_change_set::text,true);
  PERFORM set_config('app.change_seq','0',true);
  INSERT INTO import_korrektion(import_key,record_key,felt,input_fingerprint,importeret,status)
    VALUES ('verify:ocr','journal','navn','0123456789abcdef0123456789abcdef','{"navn":"OCR"}','rettet')
  ON CONFLICT (import_key,record_key,felt) DO UPDATE SET status=excluded.status;
  IF NOT EXISTS (SELECT 1 FROM change_event
                 WHERE change_set_id=v_change_set AND tabel='import_korrektion' AND op='UPDATE'
                   AND row_pk->>'id'=v_journal_id::text) THEN
    RAISE EXCEPTION 'FEJL: import_korrektion-upsert loggede ikke normalt change_event';
  END IF;

  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: Person OCR kvalitetsark — stabile nøgler, constraints, RLS og journalhistorik';
  ELSE RAISE; END IF;
END $$;

-- ===== Slægts-rod i lineage (flerslægts-forberedelse, B2) =====
-- Forvent: præcis én navnbærende rod pr. slægt, alle grene hænger under den,
-- alle grene arver samme effektive slægtsnavn, og personernes visning_efternavn
-- er UÆNDRET (migrationen må ikke røre cachen).
DO $$
DECLARE v_roedder INT; v_grene INT; v_uden_ophav INT; v_effektiv INT; v_sentinel INT;
BEGIN
  SELECT count(*) INTO v_roedder FROM lineage
   WHERE parent_lineage_id IS NULL AND slaegtsnavn IS NOT NULL;
  IF v_roedder < 1 THEN
    RAISE EXCEPTION 'FEJL: ingen slægts-rod i lineage (B2-migrationen er ikke kørt)';
  END IF;

  -- Ingen gren må stå tilbage som sideordnet rod med sit eget slægtsnavn: det er
  -- præcis den tilstand B2 fjerner, og den ville gøre roden dekorativ.
  SELECT count(*) INTO v_uden_ophav FROM lineage
   WHERE parent_lineage_id IS NULL AND kode IS NOT NULL;
  IF v_uden_ophav > 0 THEN
    RAISE EXCEPTION 'FEJL: % gren(e) med kode står uden slægts-rod', v_uden_ophav;
  END IF;

  SELECT count(*) INTO v_grene FROM lineage WHERE kode IS NOT NULL;
  SELECT count(*) INTO v_effektiv FROM lineage
   WHERE kode IS NOT NULL AND lineage_effective_slaegtsnavn(id) IS NULL;
  IF v_effektiv > 0 THEN
    RAISE EXCEPTION 'FEJL: % af % grene kan ikke udlede et slægtsnavn', v_effektiv, v_grene;
  END IF;

  -- Roden må aldrig få medlemmer: person_external_id joiner på (source_id, kode),
  -- og roden har begge NULL. Fanger en fremtidig rod der får sat kode ved et uheld.
  IF EXISTS (
    SELECT 1 FROM lineage l JOIN person_external_id pei
      ON pei.source_id = l.source_id AND pei.linje = l.kode
     WHERE l.parent_lineage_id IS NULL AND l.slaegtsnavn IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'FEJL: slægts-roden har medlemmer — den skal være en ren beholder';
  END IF;

  -- Slægts-narrativet er en SENTINEL (subjekt_id=1 = "hele slægten"), ikke en
  -- fremmednøgle til lineage 1. B2 flytter den IKKE; denne assert fastholder det.
  SELECT count(*) INTO v_sentinel FROM narrative
   WHERE subjekt_type = 'slaegt' AND subjekt_id <> 1;
  IF v_sentinel > 0 THEN
    RAISE EXCEPTION 'FEJL: % slægts-narrativ(er) er flyttet væk fra sentinel subjekt_id=1', v_sentinel;
  END IF;

  RAISE NOTICE 'OK: slægts-rod — % rod(/rødder), % grene, alle med arvet slægtsnavn', v_roedder, v_grene;
END $$;

-- Dublet-rod skal afvises af det partielle unikke indeks.
DO $$
DECLARE v_navn TEXT;
BEGIN
  SELECT slaegtsnavn INTO v_navn FROM lineage
   WHERE parent_lineage_id IS NULL AND slaegtsnavn IS NOT NULL LIMIT 1;
  BEGIN
    INSERT INTO lineage (id, source_id, kode, navn, slaegtsnavn, parent_lineage_id)
    VALUES (-99, NULL, NULL, v_navn, v_navn, NULL);
    DELETE FROM lineage WHERE id = -99;
    RAISE EXCEPTION 'FEJL: en rod nummer to for samme slægt blev accepteret';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'OK: lineage_slaegtsrod_uidx afviser dublet slægts-rod';
  END;
END $$;

-- =============================================================
-- 2026-08-01: union-redigering — red_tilfoej_partner + to-parts-invariant
-- Kører som redaktion via transaktions-lokal jwt-claim. Blokken ruller sine
-- RÆKKER tilbage til sidst (RAISE fanget af blokkens egen EXCEPTION-klausul);
-- IDENTITY-sekvenser rulles derimod ikke tilbage, så et par id-numre brændes
-- pr. kørsel. Ingen eksisterende data røres.
-- Mangler der en redaktionsprofil, FEJLER blokken — en assert der stiltiende
-- springer sig selv over er værre end ingen assert (Codex sol, 2026-08-01).
-- Hver negativ assert matcher den FORVENTEDE fejltekst, så et grønt assert
-- ikke kan skyldes en uvedkommende fejl (Codex sol runde 2).
-- =============================================================
DO $$
DECLARE
  v_uid uuid; v_fam bigint; v_a bigint; v_b bigint; v_barn bigint; v_alias bigint; v_fejl text;
BEGIN
  SELECT id INTO v_uid FROM profiles WHERE rolle='redaktion' LIMIT 1;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'FEJL: ingen redaktion-profil — union-asserts kan ikke køres'; END IF;
  PERFORM set_config('request.jwt.claim.sub', v_uid::text, true);

  v_a := red_opret_person('VERIFY far');
  v_b := red_opret_person('VERIFY mor');
  v_barn := red_opret_person('VERIFY barn');

  -- Skallen bygges råt: red_opret_union kræver to partnere fra start, og det er netop den
  -- mor-løse børne-familie fra 1939-loaderen vi vil kunne reparere.
  INSERT INTO family(type) VALUES ('vielse') RETURNING id INTO v_fam;
  INSERT INTO family_member(family_id, person_id, rolle) VALUES (v_fam, v_a, 'partner');
  INSERT INTO family_member(family_id, person_id, rolle) VALUES (v_fam, v_barn, 'barn');

  -- 1) tilføj partner virker og er idempotent
  PERFORM red_tilfoej_partner(v_fam, v_b);
  PERFORM red_tilfoej_partner(v_fam, v_b);
  IF (SELECT count(*) FROM family_member WHERE family_id=v_fam AND rolle='partner') <> 2 THEN
    RAISE EXCEPTION 'FEJL: red_tilfoej_partner gav ikke præcis 2 partnere (idempotens brudt?)';
  END IF;

  -- 1b) en tredje part afvises af RPC'en (læselaget projicerer kun p1/p2)
  v_fejl := NULL;
  BEGIN PERFORM red_tilfoej_partner(v_fam, red_opret_person('VERIFY tredje'));
  EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
  IF v_fejl IS NULL THEN RAISE EXCEPTION 'FEJL: en tredje part blev accepteret i unionen'; END IF;
  IF v_fejl NOT LIKE '%to parter%' THEN RAISE EXCEPTION 'FEJL: afvist, men af den forkerte grund: %', v_fejl; END IF;

  -- 1c) …og af tabellen selv, uden om RPC'en (fortryd-stien skriver rækker direkte tilbage)
  v_fejl := NULL;
  BEGIN
    INSERT INTO family_member(family_id, person_id, rolle)
      VALUES (v_fam, red_opret_person('VERIFY raa tredje'), 'partner');
  EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
  IF v_fejl IS NULL THEN RAISE EXCEPTION 'FEJL: rå INSERT omgik to-parts-invarianten'; END IF;
  IF v_fejl NOT LIKE '%en union har to%' THEN RAISE EXCEPTION 'FEJL: rå INSERT afvist af forkert grund: %', v_fejl; END IF;

  -- 1d) …men en legitim UPDATE af en eksisterende parts person_id må IKKE afvises
  UPDATE family_member SET person_id = red_opret_person('VERIFY mor v2')
    WHERE family_id=v_fam AND person_id=v_b AND rolle='partner';
  IF (SELECT count(*) FROM family_member WHERE family_id=v_fam AND rolle='partner') <> 2 THEN
    RAISE EXCEPTION 'FEJL: legitim partner-UPDATE ændrede antallet af parter';
  END IF;

  -- 2) et barn i familien kan ikke også blive partner
  v_fejl := NULL;
  BEGIN PERFORM red_tilfoej_partner(v_fam, v_barn);
  EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
  IF v_fejl IS NULL THEN RAISE EXCEPTION 'FEJL: barn blev accepteret som partner i samme familie'; END IF;
  IF v_fejl NOT LIKE '%allerede barn%' THEN RAISE EXCEPTION 'FEJL: afvist, men af den forkerte grund: %', v_fejl; END IF;

  -- 3) …og heller ikke en alias-post for barnet (identitets-bevidst cyklus-guard)
  v_alias := red_opret_person('VERIFY barn-alias');
  PERFORM red_samme_som(v_alias, v_barn);
  DELETE FROM family_member WHERE family_id=v_fam AND rolle='partner' AND person_id <> v_a;
  v_fejl := NULL;
  BEGIN PERFORM red_tilfoej_partner(v_fam, v_alias);
  EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
  IF v_fejl IS NULL THEN RAISE EXCEPTION 'FEJL: alias for et barn blev accepteret som part (cyklus)'; END IF;
  IF v_fejl NOT LIKE 'Cyklus:%' THEN RAISE EXCEPTION 'FEJL: afvist, men af den forkerte grund: %', v_fejl; END IF;

  -- 3b) …og heller ikke et alias for den SIDDENDE part (to parter, én person = selv-ægtefælle
  --      efter collapse). Både gennem RPC'en og udenom den.
  v_alias := red_opret_person('VERIFY far-alias');
  PERFORM red_samme_som(v_alias, v_a);
  v_fejl := NULL;
  BEGIN PERFORM red_tilfoej_partner(v_fam, v_alias);
  EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
  IF v_fejl IS NULL THEN RAISE EXCEPTION 'FEJL: alias for den siddende part blev accepteret som part nr. 2'; END IF;
  IF v_fejl NOT LIKE '%samme person%' THEN RAISE EXCEPTION 'FEJL: afvist, men af den forkerte grund: %', v_fejl; END IF;

  v_fejl := NULL;
  BEGIN INSERT INTO family_member(family_id, person_id, rolle) VALUES (v_fam, v_alias, 'partner');
  EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
  IF v_fejl IS NULL THEN RAISE EXCEPTION 'FEJL: rå INSERT omgik identitets-distinktheden'; END IF;
  IF v_fejl NOT LIKE '%samme person%' THEN RAISE EXCEPTION 'FEJL: rå INSERT afvist af forkert grund: %', v_fejl; END IF;

  -- 3c) Den OMVENDTE rækkefølge er også spærret: to parter først, samme_som bagefter.
  --      Uden denne ville håndhævelsen afhænge af redaktørens klik-rækkefølge.
  v_fejl := NULL;
  BEGIN PERFORM red_samme_som(red_opret_person('VERIFY spejl'), v_a);
  EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
  IF v_fejl IS NOT NULL THEN RAISE EXCEPTION 'FEJL: et uskyldigt samme_som-link blev afvist: %', v_fejl; END IF;

  DECLARE v_fam2 bigint; v_x bigint; v_y bigint;
  BEGIN
    v_x := red_opret_person('VERIFY union-part X');
    v_y := red_opret_person('VERIFY union-part Y');
    v_fam2 := red_opret_union(v_x, v_y, 'vielse');
    v_fejl := NULL;
    BEGIN PERFORM red_samme_som(v_y, v_x);
    EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
    IF v_fejl IS NULL THEN RAISE EXCEPTION 'FEJL: to parter i samme union blev linket som samme person'; END IF;
    IF v_fejl NOT LIKE '%samme union%' THEN RAISE EXCEPTION 'FEJL: afvist, men af den forkerte grund: %', v_fejl; END IF;
  END;

  -- 3d) En eksisterende relation må ikke kunne omskrives TIL samme_som med rå UPDATE.
  --      samme_som-identitet oprettes og fjernes som en hel relation, så dens evidens ikke
  --      stiltiende genbruges til en anden rolle eller andre endepunkter.
  DECLARE v_rel bigint; v_alias2 bigint; v_kanon2 bigint; v_anden bigint;
  BEGIN
    v_alias2 := red_opret_person('VERIFY UPDATE alias');
    v_kanon2 := red_opret_person('VERIFY UPDATE kanonisk');
    INSERT INTO relation(subjekt_type, subjekt_id, objekt_type, objekt_id, rolle)
      VALUES ('person', v_alias2, 'person', v_kanon2, 'bekendt_med')
      RETURNING id INTO v_rel;
    v_fejl := NULL;
    BEGIN
      UPDATE relation SET rolle='samme_som' WHERE id=v_rel;
      RAISE EXCEPTION 'VERIFY_UPDATE_BLEV_ACCEPTERET';
    EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
    IF v_fejl = 'VERIFY_UPDATE_BLEV_ACCEPTERET' THEN
      RAISE EXCEPTION 'FEJL: rå UPDATE kunne ændre en eksisterende relation til samme_som';
    END IF;
    IF v_fejl <> 'samme_som: rolle og endepunkter er uforanderlige — brug slet+genopret' THEN
      RAISE EXCEPTION 'FEJL: rå samme_som-UPDATE afvist af forkert grund: %', v_fejl;
    END IF;

    -- 3e) Undo-hjælperens eksisterende-række-sti bruger UPDATE og skal ramme samme guard.
    --      INSERT-stien for en slettet relation forbliver tilladt og valideres af insert-guarden.
    v_rel := red_samme_som(v_alias2, v_kanon2);
    v_anden := red_opret_person('VERIFY UPDATE andet endpoint');
    v_fejl := NULL;
    BEGIN
      PERFORM _version_upsert_row(
        'relation',
        jsonb_set((SELECT to_jsonb(r) FROM relation r WHERE r.id=v_rel),
                  '{objekt_id}', to_jsonb(v_anden), false)
      );
      RAISE EXCEPTION 'VERIFY_VERSION_UPSERT_BLEV_ACCEPTERET';
    EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
    IF v_fejl = 'VERIFY_VERSION_UPSERT_BLEV_ACCEPTERET' THEN
      RAISE EXCEPTION 'FEJL: _version_upsert_row kunne flytte et samme_som-endepunkt';
    END IF;
    IF v_fejl <> 'samme_som: rolle og endepunkter er uforanderlige — brug slet+genopret' THEN
      RAISE EXCEPTION 'FEJL: _version_upsert_row samme_som-UPDATE afvist af forkert grund: %', v_fejl;
    END IF;
  END;

  -- 4) negativ kontrol: guarden afviser ikke bare alt
  PERFORM red_tilfoej_partner(v_fam, red_opret_person('VERIFY urelateret'));
  IF (SELECT count(*) FROM family_member WHERE family_id=v_fam AND rolle='partner') <> 2 THEN
    RAISE EXCEPTION 'FEJL: en urelateret person blev ikke accepteret som part';
  END IF;

  RAISE NOTICE 'OK: red_tilfoej_partner + trg_partner_loft — guards holder (to-parts-loft i RPC og tabel, legitim partner-UPDATE, barn, identitets-cyklus, identitets-distinkthed begge veje, samme_som-immutability via rå UPDATE og _version_upsert_row, negativ kontrol)';
  RAISE EXCEPTION 'ROLLBACK_TESTDATA';
EXCEPTION WHEN others THEN
  IF SQLERRM = 'ROLLBACK_TESTDATA' THEN RAISE NOTICE 'OK: testdata rullet tilbage'; ELSE RAISE; END IF;
END $$;


-- ===== 2026-08-20: red_slet_person for en NARRATIV-BUNDET person =====
-- Lukker den åbne fejl fra 2026-08-20: funktionen er ældre end
-- private.narrative_record_publication, og FK'en derfra mod narrative(id) (uden
-- ON DELETE) blokerede sletningen for alle 551 narrativ-bundne 1939-personer.
-- Samme bugklasse som review 19 H2 (slaegtsnavn_karantaene) ovenfor.
-- Dækker samtidig person_slaegt_membership og person_lineage_membership, hvis
-- person_id er NOT NULL uden CASCADE og derfor blokerer på samme måde.
-- Kontrollerer til slut den modsatte invariant: private.source_record MÅ IKKE
-- røres — at teksten står på siden er stadig sandt efter en person er slettet.
DO $$
DECLARE
  v_actor     uuid   := gen_random_uuid();
  v_run       uuid   := gen_random_uuid();
  v_record    uuid   := gen_random_uuid();
  v_source    bigint; v_person bigint; v_narrative bigint;
  v_slaegt    bigint; v_lineage bigint;
BEGIN
  INSERT INTO auth.users(id,email) VALUES (v_actor,'slet-binding-verify@test.invalid');
  INSERT INTO profiles(id,rolle,email) VALUES (v_actor,'redaktion','slet-binding-verify@test.invalid');
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);

  v_source := (SELECT coalesce(max(id),0)+1 FROM source);
  INSERT INTO source(id,slags,titel,udgave,aar)
    VALUES (v_source,'DAA-udgave','VERIFY Slet-binding','VERIFY 2026',2026);
  v_person := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id,levende,privat,staged,visning_navn)
    VALUES (v_person,false,false,false,'VERIFY slet-binding');

  -- Kilderecord + binding: præcis den konstellation fase B lagde på de 551.
  INSERT INTO private.extraction_run(
    id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest
  ) VALUES (v_run,v_source,'slet-binding-verify','1','verify','verify',repeat('2',64),'{}');
  INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
    VALUES (v_record,v_source,'slet-binding-record','person_entry',v_run);
  v_narrative := (SELECT coalesce(max(id),0)+1 FROM narrative);
  INSERT INTO narrative(id,subjekt_type,subjekt_id,source_id,tekst,privat)
    VALUES (v_narrative,'person',v_person,v_source,'Bundet narrativ',false);
  INSERT INTO private.narrative_record_publication(
    narrative_id,source_record_id,record_label,citation_label,status
  ) VALUES (v_narrative,v_record,'Linje I, nr. 1','s. 1','published');

  -- Medlemskaber: person_id er NOT NULL uden ON DELETE CASCADE.
  INSERT INTO slaegt(navn,sorteringsnavn,slug)
    VALUES ('VERIFY Slet','VERIFY Slet','verify-slet-binding') RETURNING id INTO v_slaegt;
  INSERT INTO person_slaegt_membership(person_id,slaegt_id,membership_kind)
    VALUES (v_person,v_slaegt,'editorial');
  v_lineage := (SELECT coalesce(max(id),0)+1 FROM lineage);
  INSERT INTO lineage(id,source_id,kode,navn,slaegtsnavn)
    VALUES (v_lineage,v_source,'__VERIFY_SLET','VERIFY','Verify');
  INSERT INTO person_lineage_membership(person_id,lineage_id,role)
    VALUES (v_person,v_lineage,'member');

  -- Selve prøven: må ikke rejse FK-violation.
  PERFORM red_slet_person(v_person);

  IF EXISTS (SELECT 1 FROM person WHERE id=v_person) THEN
    RAISE EXCEPTION 'FEJL: personen blev ikke slettet';
  END IF;
  IF EXISTS (SELECT 1 FROM narrative WHERE id=v_narrative) THEN
    RAISE EXCEPTION 'FEJL: narrativet overlevede sletningen';
  END IF;
  IF EXISTS (SELECT 1 FROM private.narrative_record_publication WHERE narrative_id=v_narrative) THEN
    RAISE EXCEPTION 'FEJL: narrativ-bindingen overlevede sletningen';
  END IF;
  IF EXISTS (SELECT 1 FROM person_slaegt_membership WHERE person_id=v_person) THEN
    RAISE EXCEPTION 'FEJL: slaegt-medlemskabet overlevede sletningen';
  END IF;
  IF EXISTS (SELECT 1 FROM person_lineage_membership WHERE person_id=v_person) THEN
    RAISE EXCEPTION 'FEJL: lineage-medlemskabet overlevede sletningen';
  END IF;
  -- Modsat invariant: kilderegistreringen er stadig sand.
  IF NOT EXISTS (SELECT 1 FROM private.source_record WHERE id=v_record) THEN
    RAISE EXCEPTION 'FEJL: person-sletningen fjernede en private.source_record';
  END IF;

  RAISE NOTICE 'OK: red_slet_person — narrativ-binding + slaegt/lineage-medlemskab fjernet, source_record bevaret';
  RAISE EXCEPTION 'ROLLBACK_TESTDATA';
EXCEPTION WHEN others THEN
  IF SQLERRM = 'ROLLBACK_TESTDATA' THEN RAISE NOTICE 'OK: testdata rullet tilbage'; ELSE RAISE; END IF;
END $$;


-- ===== 2026-08-20: red_slet_person løsner haendelse-ankre i stedet for at slette =====
-- Påvist asymmetri: red_slet_person samler relationer hvor personen er subjekt ELLER objekt
-- (schema.sql), mens hændelses-loaderen forankrer efter subjekt alene
-- (.claude/skills/daa-haendelser/scripts/load_haendelser.R). En relation Q→P kan derfor bære
-- en hændelse under Q's narrativ, som IKKE cascade-slettes når P's narrativer forsvinder —
-- og haendelse.relation_id har FK uden ON DELETE. Q's hændelse skal bevares, ankeret løsnes.
DO $$
DECLARE
  v_actor  uuid := gen_random_uuid();
  v_source bigint; v_p bigint; v_q bigint; v_qnarr bigint; v_rel bigint; v_h bigint;
BEGIN
  INSERT INTO auth.users(id,email) VALUES (v_actor,'haendelse-anker-verify@test.invalid');
  INSERT INTO profiles(id,rolle,email) VALUES (v_actor,'redaktion','haendelse-anker-verify@test.invalid');
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);

  v_source := (SELECT coalesce(max(id),0)+1 FROM source);
  INSERT INTO source(id,slags,titel) VALUES (v_source,'DAA-udgave','VERIFY haendelse-anker');
  v_p := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id,levende,privat,visning_navn) VALUES (v_p,false,false,'VERIFY P (slettes)');
  v_q := v_p + 1;
  INSERT INTO person(id,levende,privat,visning_navn) VALUES (v_q,false,false,'VERIFY Q (bevares)');

  -- P er OBJEKT i relationen — red_slet_person(P) samler den alligevel i v_rels.
  v_rel := (SELECT coalesce(max(id),0)+1 FROM relation);
  INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw)
    VALUES (v_rel,'person',v_q,'person',v_p,'deltager','1930');

  -- Hændelsen hænger under Q's narrativ, ikke P's, og overlever derfor P's narrativ-sletning.
  v_qnarr := (SELECT coalesce(max(id),0)+1 FROM narrative);
  INSERT INTO narrative(id,subjekt_type,subjekt_id,source_id,tekst,privat)
    VALUES (v_qnarr,'person',v_q,v_source,'Q-biografi',false);
  v_h := (SELECT coalesce(max(id),0)+1 FROM haendelse);
  INSERT INTO haendelse(id,subjekt_type,subjekt_id,narrative_id,noegle,klausul,relation_id)
    VALUES (v_h,'person',v_q,v_qnarr,'verify-anker','deltog 1930',v_rel);

  PERFORM red_slet_person(v_p);

  IF EXISTS (SELECT 1 FROM person WHERE id=v_p) THEN
    RAISE EXCEPTION 'FEJL: P blev ikke slettet';
  END IF;
  IF EXISTS (SELECT 1 FROM relation WHERE id=v_rel) THEN
    RAISE EXCEPTION 'FEJL: relationen Q->P overlevede sletningen';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM person WHERE id=v_q) THEN
    RAISE EXCEPTION 'FEJL: Q blev slettet — kun P skulle slettes';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM haendelse WHERE id=v_h) THEN
    RAISE EXCEPTION 'FEJL: Q-haendelsen blev slettet — kun ankeret skulle loesnes';
  END IF;
  IF (SELECT relation_id FROM haendelse WHERE id=v_h) IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: haendelse.relation_id blev ikke loesnet';
  END IF;

  RAISE NOTICE 'OK: red_slet_person — Q-haendelsen bevaret, relation_id-anker loesnet';
  RAISE EXCEPTION 'ROLLBACK_TESTDATA';
EXCEPTION WHEN others THEN
  IF SQLERRM = 'ROLLBACK_TESTDATA' THEN RAISE NOTICE 'OK: testdata rullet tilbage'; ELSE RAISE; END IF;
END $$;


-- ===== 2026-08-20: red_slet_person afviser tidligt ved accepteret kilde-identitet =====
-- private.source_persona_identity_event er append-only og bærer canonical_person_id med FK mod
-- person. Har personen én gang haft en ACCEPTERET identitetsbeslutning, kan den aldrig
-- hard-slettes — heller ikke efter en tilbagetrækning. Kontrakten er, at brugeren får en
-- forståelig domænefejl FØR change_settet åbnes, ikke en rå FK-violation halvvejs igennem.
DO $$
DECLARE
  v_actor   uuid := gen_random_uuid();
  v_run     uuid := gen_random_uuid();
  v_persona uuid := gen_random_uuid();
  v_source  bigint; v_p bigint; v_fejl text;
BEGIN
  INSERT INTO auth.users(id,email) VALUES (v_actor,'persona-gate-verify@test.invalid');
  INSERT INTO profiles(id,rolle,email) VALUES (v_actor,'redaktion','persona-gate-verify@test.invalid');
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);

  v_source := (SELECT coalesce(max(id),0)+1 FROM source);
  INSERT INTO source(id,slags,titel) VALUES (v_source,'DAA-udgave','VERIFY persona-gate');
  v_p := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id,levende,privat,visning_navn) VALUES (v_p,false,false,'VERIFY persona-bundet');
  INSERT INTO private.extraction_run(
    id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest
  ) VALUES (v_run,v_source,'persona-gate-verify','1','verify','verify',repeat('3',64),'{}');
  INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
    VALUES (v_persona,v_source,'verify-persona',v_run);
  INSERT INTO private.source_persona_identity_event(
    source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at
  ) VALUES (v_persona,v_p,'accepted',1,'{"verify":true}'::jsonb,v_actor,'Verify',now());

  v_fejl := NULL;
  BEGIN
    PERFORM red_slet_person(v_p);
    RAISE EXCEPTION 'VERIFY_SLETNING_BLEV_ACCEPTERET';
  EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;

  IF v_fejl = 'VERIFY_SLETNING_BLEV_ACCEPTERET' THEN
    RAISE EXCEPTION 'FEJL: sletning af persona-bundet person blev accepteret';
  END IF;
  IF v_fejl NOT LIKE 'PERSON_HAR_KILDEIDENTITET%' THEN
    RAISE EXCEPTION 'FEJL: forkert afvisningsgrund ved persona-blokering: %', v_fejl;
  END IF;
  -- BEMÆRK: der er ingen assert på »intet change_set blev åbnet« eller »intet blev delvist
  -- slettet«. PL/pgSQL's BEGIN..EXCEPTION ovenfor er en subtransaktion, så begge dele rulles
  -- tilbage uanset hvor i funktionen afvisningen faldt — en sådan assert ville altid bestå og
  -- give falsk tryghed. At afvisningen sker før begin_change_set er sikret ved rækkefølgen i
  -- funktionen selv, ikke her.

  RAISE NOTICE 'OK: red_slet_person — persona-bundet person afvist med domaenefejl';
  RAISE EXCEPTION 'ROLLBACK_TESTDATA';
EXCEPTION WHEN others THEN
  IF SQLERRM = 'ROLLBACK_TESTDATA' THEN RAISE NOTICE 'OK: testdata rullet tilbage'; ELSE RAISE; END IF;
END $$;

-- ===== Issue #127: story_kilde i version_pk_registry + registry-dækning =====
-- Forvent: alle tre blokke ender i NOTICE 'OK: ...'.

-- 1) Registry-dækning: enhver tabel en red_*-funktion DML'er mod skal stå i
--    version_pk_registry eller være eksplicit undtaget. Undtagelserne er
--    dokumenteret: change_set (versioneringens egen infrastruktur),
--    suggestion (forslags-kø, ikke kanonisk data — versioneres ved apply, #128),
--    media_variant (afledt cache, B8-mønsteret — schema.sql-kommentar ved media_variant),
--    slaegtsnavn_karantaene (afledt, selv-helbredende karantæne-liste).
DO $$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(t.tabel, ', ' ORDER BY t.tabel) INTO v_missing
  FROM (
    SELECT DISTINCT lower(m.grp[2]) AS tabel
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    CROSS JOIN LATERAL regexp_matches(p.prosrc,
      '(INSERT INTO|UPDATE|DELETE FROM)\s+([a-zA-Z_]+)', 'gi') AS m(grp)
    WHERE n.nspname = 'public' AND p.proname LIKE 'red\_%'
  ) t
  JOIN pg_class c ON c.relname = t.tabel
    AND c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
  WHERE t.tabel NOT IN (SELECT tabel FROM version_pk_registry)
    AND t.tabel NOT IN ('change_set','suggestion','media_variant','slaegtsnavn_karantaene');
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: red_*-DML-tabeller uden versionering (fortryd = tavs no-op): %', v_missing;
  END IF;
  RAISE NOTICE 'OK: alle red_*-DML-tabeller er versioneret eller eksplicit undtaget';
END $$;

-- 2) Trigger-paritet: en registry-række uden trg_log_-trigger logger intet.
DO $$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(r.tabel, ', ' ORDER BY r.tabel) INTO v_missing
  FROM version_pk_registry r
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relnamespace = 'public'::regnamespace
      AND c.relname = r.tabel AND t.tgname = 'trg_log_' || r.tabel);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: registry-tabeller uden log_change-trigger: %', v_missing;
  END IF;
  RAISE NOTICE 'OK: alle registry-tabeller har deres trg_log_-trigger';
END $$;

-- 3) Adfærd: red_set_story_kilder logger story_kilde-events, og fortryd
--    genskaber tilstanden (var tavs no-op før #127).
DO $$
DECLARE
  v_redaktor uuid := '00000000-0000-0000-0000-0000000000d7';
  v_person bigint; v_story bigint; v_src bigint; v_cs bigint;
  v_events int; v_rows int;
BEGIN
  INSERT INTO auth.users(id,email) VALUES (v_redaktor,'verify-127@test')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,navn) VALUES (v_redaktor,'redaktion','VERIFY 127')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('request.jwt.claim.sub', v_redaktor::text, true);

  v_person := red_opret_person('VERIFY 127 person');
  INSERT INTO source(id,titel) VALUES ((SELECT coalesce(max(id),0)+1 FROM source),'VERIFY 127 kilde')
    RETURNING id INTO v_src;
  v_story := red_opret_story('person', v_person, 'VERIFY 127 story-tekst');

  -- nyt change_set specifikt for kilde-kaldet, så fortryd rammer præcist
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_set_story_kilder(v_story,
    jsonb_build_array(jsonb_build_object('source_id', v_src, 'side', '12')));
  v_cs := current_setting('app.change_set_id', true)::bigint;

  SELECT count(*) INTO v_events
    FROM change_event WHERE change_set_id = v_cs AND tabel = 'story_kilde';
  IF v_events = 0 THEN
    RAISE EXCEPTION 'FEJL: red_set_story_kilder loggede ingen story_kilde-events — fortryd er tavs no-op (#127)';
  END IF;

  -- fortryd i eget change_set: kildelisten skal være tom igen
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(v_cs);
  SELECT count(*) INTO v_rows FROM story_kilde WHERE story_id = v_story;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'FEJL: fortryd genskabte ikke tom kildeliste (% rækker tilbage)', v_rows;
  END IF;

  RAISE NOTICE 'OK: story_kilde versioneres — % events logget, fortryd genskabte tom kildeliste', v_events;
  RAISE EXCEPTION 'ROLLBACK_TESTDATA';
EXCEPTION WHEN others THEN
  IF SQLERRM = 'ROLLBACK_TESTDATA' THEN RAISE NOTICE 'OK: testdata rullet tilbage'; ELSE RAISE; END IF;
END $$;

-- Medie-metadata-faktatyper + RLS-skærpelse (2026-08-06)
DO $$
DECLARE v_n int; v_id bigint;
BEGIN
  SELECT count(*) INTO v_n FROM vocab WHERE scheme='faktatype' AND code IN
    ('kilde_url','kilde_institution','ekstern_objekt_id','hentedato','fotograf','rettighedshaver',
     'kreditlinje','beskrivelse','alt_tekst','teknik','fysiske_maal','datering');
  IF v_n <> 12 THEN RAISE EXCEPTION 'medie-metadata-seeds: forventede 12, fandt %', v_n; END IF;
  -- entitet_offentlig gater nu media på publicering (spec §1b): et upubliceret medie skal være mørkt
  SELECT id INTO v_id FROM media WHERE NOT maa_publiceres LIMIT 1;
  IF v_id IS NOT NULL AND entitet_offentlig('media', v_id) THEN
    RAISE EXCEPTION 'entitet_offentlig(media) gater ikke upubliceret medie %', v_id;
  END IF;
  -- ikke-eksisterende medie → fail-closed
  IF entitet_offentlig('media', -1) THEN
    RAISE EXCEPTION 'entitet_offentlig(media, -1) burde være false';
  END IF;
  RAISE NOTICE 'OK: medie-metadata — 12 faktatype-seeds + entitet_offentlig gater media på publicering';
END $$;

-- ===== #198: db-verify må ikke efterlade forældreløse evidens-koblinger =====
-- Baggrund: dblink-samtidighedstesten for promotion indsatte gennem en SEPARAT session en
-- interpretation_observation-række på et gen_random_uuid()-id, som oprydningens faste
-- fixture-id'er ikke dækkede. Rækken overlevede hver kørsel med BEGGE fremmednøgler
-- hængende, og ved `pg_restore --clean` kunne ingen af de to fremmednøgler genskabes
-- (målt 2026-09-17 i en fortrydelsesøvelse: 2 constraints før restore, 0 efter).
--
-- Denne assertion er selve sikringen: et fremtidigt læk af samme slags — fra denne blok
-- eller en anden — fanges her i stedet for som manglende constraints i en gendannelse.
-- Den er bevidst placeret SIDST, så den ser summen af alt, suiten har lavet.
DO $verify_ingen_foraeldreloese_evidenskoblinger$
DECLARE
  v_uden_interpretation int; v_uden_observation int;
  v_rest_io int; v_rest_interp int; v_rest_obs int; v_rest_source int;
BEGIN
  -- Tabellen er obligatorisk: den oprettes af BAADE schema.sql og db-migrations.sql, og
  -- suiten har brugt den laenge foer dette punkt. Et to_regclass-spring ville derfor ikke
  -- give kompatibilitet — det ville kun goere en paastaaet fail-closed gate fail-OPEN ved
  -- en delkoersel. (Codex-fund 2026-09-20.)
  IF to_regclass('private.interpretation_observation') IS NULL THEN
    RAISE EXCEPTION '#198 FEJL: private.interpretation_observation mangler — suiten kan ikke efterproeve sin egen oprydning';
  END IF;

  -- (1) Referentiel konsistens: ingen boern uden foraeldre. Det er den tilstand, der
  --     braekker constraint-genskabelsen ved pg_restore --clean.
  SELECT count(*) INTO v_uden_interpretation
    FROM private.interpretation_observation io
   WHERE NOT EXISTS (SELECT 1 FROM private.interpretation i WHERE i.id = io.interpretation_id);
  SELECT count(*) INTO v_uden_observation
    FROM private.interpretation_observation io
   WHERE NOT EXISTS (SELECT 1 FROM private.source_observation o WHERE o.id = io.observation_id);

  -- (2) Faktisk oprydning. Konsistens alene beviser INTET om oprydning: efterlader en
  --     regression baade den tilfaeldige interpretation, dens koblinger OG observationen,
  --     er alle fremmednoegler gyldige, og (1) ville vaere groen. Derfor maales ogsaa, at
  --     selve fixture-domaenet er tomt. (Codex-fund 2026-09-20.)
  SELECT count(*) INTO v_rest_source FROM source WHERE id = -987650051;
  SELECT count(*) INTO v_rest_obs
    FROM private.source_observation WHERE id = '66000000-0000-0000-0000-000000000051';
  SELECT count(*) INTO v_rest_interp
    FROM private.interpretation
   WHERE source_id = -987650051
      OR id IN ('c1000000-0000-0000-0000-000000000051','c1000000-0000-0000-0000-000000000052',
                'c1000000-0000-0000-0000-000000000053','c1000000-0000-0000-0000-000000000054');
  SELECT count(*) INTO v_rest_io
    FROM private.interpretation_observation
   WHERE observation_id = '66000000-0000-0000-0000-000000000051'
      OR interpretation_id IN ('c1000000-0000-0000-0000-000000000051','c1000000-0000-0000-0000-000000000052',
                               'c1000000-0000-0000-0000-000000000053','c1000000-0000-0000-0000-000000000054')
      OR interpretation_id IN (SELECT id FROM private.interpretation WHERE source_id = -987650051);

  IF v_uden_interpretation = 0 AND v_uden_observation = 0
     AND v_rest_io = 0 AND v_rest_interp = 0 AND v_rest_obs = 0 AND v_rest_source = 0 THEN
    RAISE NOTICE 'OK: #198 — ingen forældreløse evidens-koblinger OG intet fixture-restindhold efter suiten';
  ELSE
    RAISE EXCEPTION '#198 FEJL: forældreløse: % uden interpretation, % uden source_observation | fixture-rester: % koblinger, % fortolkninger, % observationer, % kilder',
      v_uden_interpretation, v_uden_observation, v_rest_io, v_rest_interp, v_rest_obs, v_rest_source;
  END IF;
END
$verify_ingen_foraeldreloese_evidenskoblinger$;
