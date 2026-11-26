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

-- Review 37 A2: hændelser ændrer ikke en biografis publiceringstilstand; låsen læses via én privat hjælper.
-- Adfærden (uændret synlighed, ændret editor-token, afvist revise) bevises i test-narrative-record-contract.sql.
DO $review37_a2_verify$
DECLARE
  v_role text;
  v_function text;
  v_count bigint;
BEGIN
  IF to_regprocedure('private.narrative_har_haendelse(bigint)') IS NULL THEN
    RAISE EXCEPTION 'REVIEW37_A2_HELPER_MISSING';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc function
     WHERE function.oid='private.narrative_har_haendelse(bigint)'::regprocedure
       AND (function.provolatile<>'s' OR function.prosecdef
            OR function.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[])
  ) THEN
    RAISE EXCEPTION 'REVIEW37_A2_HELPER_FORM_INVALID';
  END IF;
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_function_privilege(v_role,'private.narrative_har_haendelse(bigint)','EXECUTE') THEN
      RAISE EXCEPTION 'REVIEW37_A2_HELPER_ACL_INVALID: %',v_role;
    END IF;
  END LOOP;

  -- (b) Ingen publiceringstilstand læser hændelser.
  FOREACH v_function IN ARRAY ARRAY[
    'private.narrative_publication_state(bigint,bigint,text)',
    'private.narrative_legacy_candidate_publication_state(bigint,bigint,uuid)',
    'private.narrative_legacy_publication_state(uuid)'
  ] LOOP
    IF strpos(pg_get_functiondef(v_function::regprocedure),'public.haendelse')<>0
       OR strpos(pg_get_functiondef(v_function::regprocedure),'narrative_har_haendelse(')<>0 THEN
      RAISE EXCEPTION 'REVIEW37_A2_STATE_READS_HAENDELSE: %',v_function;
    END IF;
  END LOOP;
  SELECT count(*) INTO v_count
    FROM (
      SELECT DISTINCT narrative.subjekt_id AS person_id,record.source_id,record.record_key
        FROM private.narrative_record_publication binding
        JOIN public.narrative narrative ON narrative.id=binding.narrative_id
        JOIN private.source_record record ON record.id=binding.source_record_id
       WHERE narrative.subjekt_type='person'
         AND EXISTS (SELECT 1 FROM public.haendelse event WHERE event.narrative_id=binding.narrative_id)
    ) k
    CROSS JOIN LATERAL private.narrative_publication_state(k.person_id,k.source_id,k.record_key) state
   WHERE (state->>'has_haendelse') IS DISTINCT FROM 'false'
      OR ((state->'narrative') IS NOT NULL AND jsonb_typeof(state->'narrative')='object'
          AND (state #>> '{narrative,has_haendelse}') IS DISTINCT FROM 'false');
  IF v_count<>0 THEN
    RAISE EXCEPTION 'REVIEW37_A2_HAS_HAENDELSE_NOT_FALSE: %',v_count;
  END IF;

  -- (c) Låsen (text_editable og revise) læses via hjælperen, ikke via publication_state.
  FOREACH v_function IN ARRAY ARRAY[
    'private.narrative_record_state(bigint,bigint,text,boolean)',
    'private.mutate_person_narrative_record(text,bigint,bigint,text,text,boolean,text)',
    -- Codex r1: fortrydelse og historikkens can_reverse bruger samme lås.
    'private.reverse_narrative_publication_event(uuid,text)',
    'public.red_person_narrative_publication_history(bigint)'
  ] LOOP
    IF strpos(pg_get_functiondef(v_function::regprocedure),'private.narrative_har_haendelse(')=0
       OR strpos(pg_get_functiondef(v_function::regprocedure),'''has_haendelse'')::boolean')<>0 THEN
      RAISE EXCEPTION 'REVIEW37_A2_LOCK_NOT_VIA_HELPER: %',v_function;
    END IF;
  END LOOP;

  RAISE NOTICE 'OK: review 37 A2 — has_haendelse udfaset, hændelseslås via private.narrative_har_haendelse';
END
$review37_a2_verify$;

-- Review 37 Y3: feedets hændelser i bidder. Adfærden (RLS-lighed, tom bid, gate pr. narrativ, mærke) bevises i
-- tests/sql/test-haendelse-feed.sql; her form, ACL, nøgle og fejlkoder.
DO $review37_y3_verify$
DECLARE
  f regprocedure:=to_regprocedure('public.public_haendelse_feed(text,integer,integer)');
  v_def text;
  v_role text;
  v_fejl text;
  v_kald text;
BEGIN
  IF f IS NULL OR to_regclass('private.feed_cursor_noegle') IS NULL
     OR to_regclass('public.ix_haendelse_narrative_id') IS NULL THEN
    RAISE EXCEPTION 'REVIEW37_Y3_MISSING';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=f
              AND (NOT p.prosecdef OR p.provolatile<>'s'
                   OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[])) THEN
    RAISE EXCEPTION 'REVIEW37_Y3_FORM_INVALID';
  END IF;
  IF NOT has_function_privilege('anon',f,'EXECUTE') OR NOT has_function_privilege('authenticated',f,'EXECUTE')
     OR has_function_privilege('service_role',f,'EXECUTE')
     OR EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid=f AND a.grantee=0) THEN
    RAISE EXCEPTION 'REVIEW37_Y3_ACL_INVALID';
  END IF;
  v_def:=pg_get_functiondef(f);
  -- Samme regel for alle roller (projektejeren 2026-11-21): ingen afhængighed af kalderens rolle.
  IF strpos(v_def,'current_rolle')<>0 OR strpos(v_def,'auth.uid')<>0
     OR strpos(v_def,'public.person_daa_narrative_publication_allowed(n.narrative_id)')=0
     OR strpos(v_def,'h.feed_status<>''skjult''')=0
     OR strpos(v_def,'public.entitet_offentlig(h.subjekt_type,h.subjekt_id)')=0
     OR strpos(v_def,'extensions.pgp_sym_encrypt(')=0 THEN
    RAISE EXCEPTION 'REVIEW37_Y3_FILTER_OR_CURSOR_MISSING';
  END IF;
  IF (SELECT count(*) FROM private.feed_cursor_noegle)<>1 THEN
    RAISE EXCEPTION 'REVIEW37_Y3_KEY_ROW_INVALID';
  END IF;
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_table_privilege(v_role,'private.feed_cursor_noegle','SELECT')
       OR has_table_privilege(v_role,'private.feed_cursor_noegle','UPDATE') THEN
      RAISE EXCEPTION 'REVIEW37_Y3_KEY_ACL_INVALID: %',v_role;
    END IF;
  END LOOP;
  FOREACH v_kald IN ARRAY ARRAY['limit:0','limit:2001','cursor'] LOOP
    BEGIN
      IF v_kald='limit:0' THEN PERFORM public.public_haendelse_feed(NULL,0,10);
      ELSIF v_kald='limit:2001' THEN PERFORM public.public_haendelse_feed(NULL,10,2001);
      ELSE PERFORM public.public_haendelse_feed('ikke-et-maerke',10,10); END IF;
      RAISE EXCEPTION 'REVIEW37_Y3_ACCEPTED: %',v_kald;
    EXCEPTION WHEN others THEN
      GET STACKED DIAGNOSTICS v_fejl=MESSAGE_TEXT;
      IF v_fejl IS DISTINCT FROM (CASE WHEN v_kald='cursor' THEN 'FEED_CURSOR_INVALID' ELSE 'FEED_LIMIT_INVALID' END) THEN
        RAISE;
      END IF;
    END;
  END LOOP;
  RAISE NOTICE 'OK: review 37 Y3 — public_haendelse_feed er DEFINER, gatet pr. narrativ for alle roller, privat nøgle, fejlkoder';
END
$review37_y3_verify$;


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
    -- Trin 6a: tekstversionens provenance-kolonner findes, er valgfrie, og helpost_text_current finder versionen.
    IF NOT EXISTS (SELECT 1 FROM private.source_observation_text
                    WHERE id='61000000-0000-0000-0000-000000000001'
                      AND extraction_run_id IS NULL AND method IS NULL AND evidence IS NULL)
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                       WHERE table_schema='private' AND table_name='source_observation' AND column_name='parent_text_id')
       OR (SELECT text_id FROM private.helpost_text_current(v_observation))
            IS DISTINCT FROM '61000000-0000-0000-0000-000000000001'::uuid THEN
      RAISE EXCEPTION 'FEJL: tekstversionens kolonner eller helpost_text_current mangler';
    END IF;
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
  -- Trin 6a (spec §4.4 pkt. 6): S4 åbner kun på revisions-events (superseded_keys), og nøglen kan være v2.
  IF v_def NOT LIKE '%e.operation=''source_text_revision''%' OR v_def NOT LIKE '%superseded_keys%'
     OR v_def NOT LIKE '%interpretation_proposal_key_material_v2(%' THEN
    RAISE EXCEPTION 'FEJL: write_interpretation_proposal mangler genkørselskontrakten (S4-åbning, nøgle v2)';
  END IF;
  -- Trin 6c-1: forslagswriteren vælger helposten med helpost-reglen, og slagsen læses fra writerprofilen.
  IF v_def NOT LIKE '%record_helpost_observation(%' OR v_def NOT LIKE '%writer_config_helpost_kind(%' THEN
    RAISE EXCEPTION 'FEJL: write_interpretation_proposal følger ikke helpost-reglen (record_helpost_observation/writer_config_helpost_kind)';
  END IF;
  v_def:=pg_get_functiondef(to_regprocedure('private.write_clause_evidence(uuid,text,jsonb)'));
  IF v_def IS NULL OR v_def NOT LIKE '%private.clause_write_set(%' THEN
    RAISE EXCEPTION 'FEJL: write_clause_evidence skriver ikke via clause_write_set';
  END IF;
  v_def:=pg_get_functiondef(to_regprocedure('private.clause_write_set(jsonb,jsonb,integer,text,uuid)'));
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
     OR to_regprocedure('private.interpretation_proposal_key_material_v2(bigint,text,text,jsonb,jsonb,integer)') IS NULL
     OR to_regprocedure('private.write_interpretation_proposal(uuid,text,jsonb)') IS NULL
     OR to_regprocedure('public.red_apply_reimport_interpretation_proposal(uuid,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'MISSING: #147 4.4 interpretation_proposal writer';
  END IF;
  IF pg_get_functiondef('private.validate_reimport_authorization_payload(jsonb,jsonb)'::regprocedure) NOT LIKE '%interpretation-proposal:%'
     OR has_function_privilege('anon','public.red_apply_reimport_interpretation_proposal(uuid,text,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_apply_reimport_interpretation_proposal(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.interpretation_proposal_canonical_json_text(jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.interpretation_proposal_key(bigint,text,text,jsonb,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.interpretation_proposal_key_material_v2(bigint,text,text,jsonb,jsonb,integer)','EXECUTE')
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
    'public.red_apply_reimport_source_text_revision(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_reimport_interpretation_proposal(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_reimport_relation_persona(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_reimport_publication_persona(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_reimport_record_persona(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_reimport_publication_identity(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_reimport_relation_person_create(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_reimport_relation_disposition(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_reimport_person_create(uuid,text,jsonb)'::regprocedure,
    'public.red_apply_reimport_source_evidence(uuid,text,jsonb)'::regprocedure,
    'public.red_begin_1939_v50_name_completion(uuid,text,uuid)'::regprocedure,
    'public.red_begin_1939_v50_reimport(uuid,text,text)'::regprocedure,
    'public.red_begin_reimport(uuid,text,text)'::regprocedure,
    'public.red_begin_reimport_name_completion(uuid,text,uuid)'::regprocedure,
    'public.red_bekraeft_media_upload(bigint,bigint,text)'::regprocedure,
    'public.red_classify_parent_card(uuid,uuid,integer,text,text,jsonb)'::regprocedure,
    'public.red_corroborate_family_identities(uuid,text)'::regprocedure,
    'public.red_decide_interpretation(uuid,integer,text,jsonb)'::regprocedure,
    'public.red_decide_relation_interpretations(bigint,text)'::regprocedure,
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
    'public.red_register_identity_control_run(uuid,text)'::regprocedure,
    'public.red_relation_persona_input(bigint)'::regprocedure,
    'public.red_relation_person_create_input(bigint)'::regprocedure,
    'public.red_relation_persona_v2_input(bigint)'::regprocedure,
    'public.red_relation_persona_v3_input(bigint)'::regprocedure,
    'public.red_relation_child_sheet_input(bigint)'::regprocedure,
    'public.red_marriage_ordinal_correction_input(bigint)'::regprocedure,
    'public.red_ret_aegteskabsnummer(uuid,integer,text,jsonb)'::regprocedure,
    'public.red_genaabn_relation_interpretation(uuid,integer,text,jsonb)'::regprocedure,
    'public.red_preview_placement_memberships(bigint)'::regprocedure,
    'public.red_promote_placement_memberships(bigint,text)'::regprocedure,
    'public.red_reverse_placement_membership(bigint,bigint,text)'::regprocedure,
    'public.red_relation_disposition_input(bigint)'::regprocedure,
    'public.red_ikke_samme_som(bigint,bigint)'::regprocedure,
    'public.red_kasser_person_narrative_record(bigint,bigint,text,text)'::regprocedure,
    'public.red_lock_1939_v50_name_completion(text)'::regprocedure,
    'public.red_lock_reimport_name_completion(text,bigint,text)'::regprocedure,
    'public.red_match_personer()'::regprocedure,
    'public.red_normaliser_forslag(uuid,integer,text)'::regprocedure,
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
    'public.red_paastand_historik(bigint)'::regprocedure,
    'public.red_person_grid()'::regprocedure,
    'public.red_person_grid_udsnit(bigint,integer,bigint)'::regprocedure,
    'public.red_person_narrative_publication_history(bigint)'::regprocedure,
    'public.red_person_narrative_records(bigint)'::regprocedure,
    'public.red_overview_mentions(bigint[])'::regprocedure,
    'public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb)'::regprocedure,
    'public.red_preflight_reimport_authorization(uuid,text,text)'::regprocedure,
    'public.red_preflight_reimport_name_completion(uuid,uuid,text,jsonb)'::regprocedure,
    'public.red_preview_interpretation_promotions(jsonb)'::regprocedure,
    'public.red_preview_relation_decisions(bigint)'::regprocedure,
    'public.red_preview_relation_promotions(bigint,jsonb)'::regprocedure,
    'public.red_promote_relation_interpretations_batch(bigint,jsonb,text)'::regprocedure,
    'public.red_preview_reimport_cases(bigint,text,jsonb)'::regprocedure,
    'public.red_promote_interpretations_batch(jsonb,text)'::regprocedure,
    'public.red_publication_control(uuid)'::regprocedure,
    'public.red_publication_control_details(uuid)'::regprocedure,
    'public.red_publicer_person_narrative_record(bigint,bigint,text,text)'::regprocedure,
    'public.red_publicer_personer(bigint[])'::regprocedure,
    'public.red_publicer_udgave(bigint)'::regprocedure,
    'public.red_record_identity_candidates(jsonb,jsonb)'::regprocedure,
    'public.red_rediger_story(bigint,text,text,bigint,bigint,bigint,bigint,date,date,text,text,boolean)'::regprocedure,
    'public.red_registrer_media_variant(bigint,text,text,text,bigint,integer,integer)'::regprocedure,
    'public.red_reimport_batch_result(uuid,uuid)'::regprocedure,
    'public.red_relation(text,bigint,text,bigint,text,text)'::regprocedure,
    'public.red_ret_ocr_felt(bigint,text,text,text,text,jsonb,text,text)'::regprocedure,
    'public.red_ret_forslag(uuid,integer,text,jsonb)'::regprocedure,
    'public.red_ret_ocr_paastand(bigint,jsonb,jsonb)'::regprocedure,
    'public.red_ret_paastand(bigint,jsonb,text,uuid,jsonb)'::regprocedure,
    'public.red_revalider_person_narrative_record(bigint,bigint,text,text)'::regprocedure,
    'public.red_reverse_1939_v50_reimport(uuid,uuid)'::regprocedure,
    'public.red_reverse_reimport(uuid,uuid)'::regprocedure,
    'public.red_reverse_reimport_publication(uuid,uuid)'::regprocedure,
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
    'public.red_set_levende(bigint,boolean)'::regprocedure,
    'public.red_set_privat(bigint,boolean)'::regprocedure,
    'public.red_set_story_kilder(bigint,jsonb)'::regprocedure,
    'public.red_set_story_status(bigint,text)'::regprocedure,
    'public.red_slet_familie_link(bigint,bigint,text)'::regprocedure,
    'public.red_slet_medierelation_uden_evidens(bigint)'::regprocedure,
    'public.red_slet_oplysning(bigint)'::regprocedure,
    'public.red_slet_person(bigint)'::regprocedure,
    'public.red_slet_person_preview(bigint)'::regprocedure,
    'public.red_slet_person_helt(bigint,text)'::regprocedure,
    'public.red_slet_person_helt_preview(bigint)'::regprocedure,
    'public.red_slettede_personer(integer)'::regprocedure,
    'public.red_person_purge_udbakke()'::regprocedure,
    'public.red_person_purge_udbakke_kvitter(text,text)'::regprocedure,
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

-- ===== #150 trin 5c-1: placement-header som strukturel forekomst (sti ii) og nærmeste-reglen =====
DO $placement_header_150_verify$
DECLARE v_source bigint; v_n bigint; v_human bigint:=0; r text;
BEGIN
  IF (SELECT count(*) FROM private.vocab WHERE scheme='observation_kind'
       AND code IN ('header_linje','header_slaegtled','header_kuld','header_aegteskab'))<>4 THEN
    RAISE EXCEPTION 'FEJL: #150 header-vokabularet mangler';
  END IF;
  IF to_regprocedure('private.placement_header_violations(bigint)') IS NULL
     OR position('header_linje' IN pg_get_functiondef('private.validate_source_record_placement()'::regprocedure))=0 THEN
    RAISE EXCEPTION 'FEJL: #150 placement-header sti ii mangler';
  END IF;
  IF has_function_privilege('anon','private.placement_header_violations(bigint)','EXECUTE')
     OR has_function_privilege('authenticated','private.placement_header_violations(bigint)','EXECUTE') THEN
    RAISE EXCEPTION 'FEJL: placement_header_violations er API-eksekverbar';
  END IF;
  -- Trin 6d-1 (decisions 2026-11-09): tælleren for menneskebekræftede overskriftsniveauer er privat.
  IF to_regprocedure('private.placement_human_header_levels(bigint)') IS NULL THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6d-1 mangler private.placement_human_header_levels(bigint)';
  END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r,'private.placement_human_header_levels(bigint)','EXECUTE') THEN
      RAISE EXCEPTION 'VERIFY_FAILED: 6d-1 placement_human_header_levels eksekverbar for %',r;
    END IF;
  END LOOP;
  FOR v_source IN SELECT DISTINCT sr.source_id FROM private.source_record_placement_current pc
                    JOIN private.source_record sr ON sr.id=pc.source_record_id WHERE pc.decision_status='accepted' LOOP
    v_n:=private.placement_header_violations(v_source);
    IF v_n<>0 THEN RAISE EXCEPTION 'FEJL: PLACEMENT_HEADER_VIOLATIONS source=% n=%',v_source,v_n; END IF;
    v_human:=v_human+private.placement_human_header_levels(v_source);
  END LOOP;
  -- Helbred, ikke fejl: placements hvis nærmeste-tjek er undtaget for et menneskebekræftet niveau.
  RAISE NOTICE 'PLACEMENT_HUMAN_HEADER_LEVELS n=%',v_human;
  RAISE NOTICE 'OK: placement-header sti ii og nærmeste-reglen';
END $placement_header_150_verify$;

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
     OR to_regprocedure('private.add_interpretation_promotion_rule_version(text,text,text,text,text,text,boolean,boolean,boolean,text,text)') IS NULL THEN
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
     WHERE rule_version=1 AND status='active' AND rule_mode='text_assertion'   -- 5b 2a: strukturregler tjekkes for sig
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
      (-987650044,'person',-987650042,'navn'),
      (-987650045,'person',-987650041,'navn'),
      (-987650046,'person',-987650041,'navn'),
      (-987650047,'person',-987650041,'navn');
    INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,calendar,uforanderlig) VALUES
      (-987650041,'fact',-987650041,'Anna Verify','gregoriansk',true),
      (-987650042,'fact',-987650042,'Anna Verify','gregoriansk',true),
      (-987650043,'fact',-987650043,'Anden tekst','gregoriansk',true),
      (-987650044,'fact',-987650044,'Anna Verify','gregoriansk',true),
      (-987650045,'fact',-987650045,'Anna Verify','gregoriansk',true),
      (-987650046,'fact',-987650046,'Anna Verify','gregoriansk',true),
      (-987650047,'fact',-987650047,'Anna Verify','gregoriansk',true);
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

    -- Trin 6c-2b: højst én gældende binding pr. påstand. En anden fortolkning mod den bundne påstand afvises.
    SET LOCAL ROLE authenticated;
    v_preview:=red_preview_interpretation_promotions(jsonb_build_array(
      jsonb_build_object('interpretation_id',v_accepted_2,'target_type','assertion','target_id',-987650041)
    ));
    RESET ROLE;
    IF v_preview->'items'->0->>'reason_code' IS DISTINCT FROM 'ALREADY_BOUND_OTHER' THEN
      RAISE EXCEPTION 'FEJL: en anden fortolkning kunne bindes til en bundet påstand: %',v_preview;
    END IF;

    -- To forskellige accepterede fortolkninger i én gyldig batch (hver sin påstand) giver præcis
    -- to audit-links og én ny batch; de opretter ikke kanoniske rækker.
    SELECT count(*) INTO v_before_promotions FROM private.interpretation_promotion;
    SELECT count(*) INTO v_before_batches FROM private.interpretation_promotion_batch;
    SELECT count(*) INTO v_before_persons FROM person;
    SELECT count(*) INTO v_before_facts FROM fact;
    SELECT count(*) INTO v_before_assertions FROM assertion;
    SET LOCAL ROLE authenticated;
    v_preview:=red_preview_interpretation_promotions(jsonb_build_array(
      jsonb_build_object('interpretation_id',v_accepted_2,'target_type','assertion','target_id',-987650045),
      jsonb_build_object('interpretation_id',v_accepted_3,'target_type','assertion','target_id',-987650046)
    ));
    PERFORM red_promote_interpretations_batch(jsonb_build_array(
      jsonb_build_object('interpretation_id',v_accepted_2,'target_type','assertion','target_id',-987650045),
      jsonb_build_object('interpretation_id',v_accepted_3,'target_type','assertion','target_id',-987650046)
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
      jsonb_build_object('interpretation_id',v_accepted_principal,'target_type','assertion','target_id',-987650047),
      jsonb_build_object('interpretation_id',v_accepted_1,'target_type','assertion','target_id',-987650044)
    ));
    v_error:=NULL;
    BEGIN
      PERFORM red_promote_interpretations_batch(jsonb_build_array(
        jsonb_build_object('interpretation_id',v_accepted_principal,'target_type','assertion','target_id',-987650047),
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
  FOREACH v_table IN ARRAY ARRAY['identity_control_run','identity_control_sample','identity_control_event',
      'identity_control_exclusion','identity_control_parent_card','identity_control_parent_event'] LOOP
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


-- ===== visning-floruit (spec 2026-11-19-visning-floruit-design.md §5): »Nævnes …« som cache =====
-- Katalogblokken har ingen fixtures og ingen BEGIN/ROLLBACK, så prod-ceremonien kan køre netop den inde i sin
-- transaktion. Forvent: NOTICE "OK: visning-floruit katalog".
DO $verify_visning_floruit$
DECLARE v_tgtype int; v_cols text[]; v_qual boolean; v_fn oid; v_uenige bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='person'
                  AND column_name='visning_floruit' AND data_type='text') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-floruit: person.visning_floruit mangler';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.version_pk_registry WHERE tabel='person' AND 'visning_floruit'=ANY(skip_cols)) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-floruit: visning_floruit står ikke i skip_cols for person';
  END IF;
  IF NOT has_column_privilege('anon','public.person','visning_floruit','SELECT')
     OR NOT has_column_privilege('authenticated','public.person','visning_floruit','SELECT') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-floruit: anon/authenticated kan ikke læse visning_floruit';
  END IF;
  -- Beregningen ligger i regen_person_floruit, som den fulde regen kalder til sidst; familie-, medlemskabs- og
  -- offentlighedsstierne kalder KUN regen_person_floruit (rører aldrig de seks øvrige visning_*).
  IF to_regprocedure('public.regen_person_floruit(bigint)') IS NULL
     OR to_regprocedure('public.regen_familie_partnere(bigint)') IS NULL
     OR strpos(pg_get_functiondef('public.regen_person_visning(bigint)'::regprocedure),'PERFORM regen_person_floruit(pid);')=0
     OR strpos(pg_get_functiondef('public.regen_familie_partnere(bigint)'::regprocedure),'regen_person_floruit')=0
     OR strpos(pg_get_functiondef('public.regen_familie_partnere(bigint)'::regprocedure),'regen_person_visning')>0
     OR strpos(pg_get_functiondef('public.trg_regen_from_family_member()'::regprocedure),'regen_person_visning')>0
     OR strpos(pg_get_functiondef('public.trg_regen_from_person_offentlighed()'::regprocedure),'regen_person_visning')>0
     OR strpos(pg_get_functiondef('public.trg_regen_from_conclusion()'::regprocedure),'regen_familie_partnere')=0
     OR strpos(pg_get_functiondef('public.trg_regen_from_assertion()'::regprocedure),'regen_familie_partnere')=0 THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-floruit: beregning, familie-gren eller floruit-alene-stierne mangler';
  END IF;
  -- family_member: AFTER INSERT OR DELETE OR UPDATE OF family_id, person_id, rolle, konfidens, FOR EACH ROW (tgtype 29).
  SELECT t.tgtype, (SELECT array_agg(a.attname::text ORDER BY a.attname) FROM pg_attribute a
                     WHERE a.attrelid=t.tgrelid AND a.attnum=ANY(t.tgattr)), t.tgfoid
    INTO v_tgtype, v_cols, v_fn
    FROM pg_trigger t WHERE t.tgrelid='public.family_member'::regclass AND t.tgname='trg_family_member_regen'
     AND t.tgenabled='O';
  IF v_tgtype IS DISTINCT FROM 29 OR v_cols IS DISTINCT FROM ARRAY['family_id','konfidens','person_id','rolle']
     OR v_fn IS DISTINCT FROM 'public.trg_regen_from_family_member()'::regprocedure::oid THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-floruit: family_member-triggeren mangler eller har forkerte events';
  END IF;
  -- person: AFTER UPDATE OF levende, privat, staged, FOR EACH ROW (tgtype 17) med WHEN; kolonnebegrænsningen sikrer,
  -- at regen_person_visning's og regen_person_floruit's egne UPDATEs af visning_* ikke udløser den igen.
  v_tgtype:=NULL; v_cols:=NULL; v_fn:=NULL;
  SELECT t.tgtype, (SELECT array_agg(a.attname::text ORDER BY a.attname) FROM pg_attribute a
                     WHERE a.attrelid=t.tgrelid AND a.attnum=ANY(t.tgattr)), t.tgqual IS NOT NULL, t.tgfoid
    INTO v_tgtype, v_cols, v_qual, v_fn
    FROM pg_trigger t WHERE t.tgrelid='public.person'::regclass AND t.tgname='trg_person_offentlighed_regen'
     AND t.tgenabled='O';
  IF v_tgtype IS DISTINCT FROM 17 OR v_cols IS DISTINCT FROM ARRAY['levende','privat','staged'] OR NOT coalesce(v_qual,false)
     OR v_fn IS DISTINCT FROM 'public.trg_regen_from_person_offentlighed()'::regprocedure::oid THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-floruit: person-triggeren mangler eller har forkerte events';
  END IF;
  -- De nye hjælpere er lukket for klientroller (eksplicit REVOKE; NULL-ACL ville betyde PUBLIC-EXECUTE).
  FOR v_fn IN SELECT to_regprocedure(s)::oid FROM unnest(ARRAY['public.regen_person_floruit(bigint)',
      'public.regen_familie_partnere(bigint)','public.trg_regen_from_family_member()',
      'public.trg_regen_from_person_offentlighed()','public.trg_regen_from_samme_som()',
      'public.person_gruppe_skjult(bigint)']) s LOOP
    IF v_fn IS NULL OR (SELECT proacl FROM pg_proc WHERE oid=v_fn) IS NULL
       OR EXISTS (SELECT 1 FROM pg_proc pr, aclexplode(pr.proacl) a WHERE pr.oid=v_fn AND a.grantee=0)
       OR has_function_privilege('anon',v_fn,'EXECUTE') OR has_function_privilege('authenticated',v_fn,'EXECUTE')
       OR (EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role')
           AND has_function_privilege('service_role',v_fn,'EXECUTE')) THEN
      RAISE EXCEPTION 'VERIFY_FAILED: visning-floruit: % mangler eller er kaldbar af en klientrolle', v_fn::regprocedure;
    END IF;
  END LOOP;
  -- regen_person_floruit og triggerne er SECURITY INVOKER og forudsætter, at kun ejeren og SECURITY DEFINER-skrivere
  -- ændrer kildetabellerne; en RLS-bundet skriver ville kunne skjule medlemmer for den inlinede regel (fail-open).
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
              AND tablename IN ('person','family_member','conclusion','assertion','relation')
              AND cmd IN ('INSERT','UPDATE','DELETE','ALL')) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-floruit: skrive-policy på person/family_member/conclusion/assertion/relation';
  END IF;
  -- Offentlighedsreglen er inlinet i regen_person_floruit (family_offentlig defineres først i db-rls.sql);
  -- den skal være enig med family_offentlig for alle familier i basen. Kravet om mindst ét medlem (review 37 S3)
  -- står ikke i den inlinede kopi: floruit læser kun familier, hvor personen selv er partner, altså aldrig en tom.
  SELECT count(*) INTO v_uenige FROM public.family f
   WHERE public.family_offentlig(f.id) IS DISTINCT FROM (
         EXISTS (SELECT 1 FROM public.family_member m0 WHERE m0.family_id=f.id)
         AND NOT EXISTS (
           SELECT 1 FROM public.family_member m JOIN public.person q ON q.id=m.person_id
            WHERE m.family_id=f.id
              AND (q.levende IS NOT FALSE OR coalesce(q.privat,false) OR coalesce(q.staged,false)
                   OR public.person_gruppe_skjult(q.id))));
  IF v_uenige<>0 THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-floruit: inlinet offentlighedsregel uenig med family_offentlig for % familier', v_uenige;
  END IF;
  RAISE NOTICE 'OK: visning-floruit katalog';
END $verify_visning_floruit$;

-- Adfærdsblokkene (kun CI, lokalt og generalprøve; aldrig i prod-transaktionen): syntetiske negative id'er, hele
-- fixturen rulles tilbage.
BEGIN;
CREATE FUNCTION pg_temp.vf_tjek(p_pid bigint, p_forventet text, p_trin text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v text;
BEGIN
  SELECT visning_floruit INTO v FROM public.person WHERE id=p_pid;
  IF v IS DISTINCT FROM p_forventet THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-floruit %: person % forventede %, fik %', p_trin, p_pid,
      coalesce(p_forventet,'NULL'), coalesce(v,'NULL');
  END IF;
END $f$;

CREATE FUNCTION pg_temp.vf_offentlig(p_fam bigint, p_forventet boolean, p_trin text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  IF public.family_offentlig(p_fam) IS DISTINCT FROM p_forventet
     OR (EXISTS (SELECT 1 FROM public.family_member m0 WHERE m0.family_id=p_fam)
         AND NOT EXISTS (SELECT 1 FROM public.family_member m JOIN public.person q ON q.id=m.person_id
                      WHERE m.family_id=p_fam
                        AND (q.levende IS NOT FALSE OR coalesce(q.privat,false) OR coalesce(q.staged,false)
                             OR public.person_gruppe_skjult(q.id))))
        IS DISTINCT FROM p_forventet THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-floruit %: family_offentlig og den inlinede regel er ikke begge %', p_trin, p_forventet;
  END IF;
END $f$;

-- Forvent: NOTICE "OK: visning-floruit spaend".
DO $verify_visning_floruit_spaend$
DECLARE
  p CONSTANT bigint := -987715001; p_aaben CONSTANT bigint := -987715002; p_tom CONSTANT bigint := -987715003;
BEGIN
  INSERT INTO person(id,levende,privat) VALUES (p,false,false),(p_aaben,false,false),(p_tom,false,false);
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES
    (-987715011,'person',p,'floruit'),(-987715012,'person',p,'titel'),(-987715013,'person',p,'fødsel'),
    (-987715014,'person',p,'begravelse'),(-987715015,'person',p,'erhverv'),(-987715016,'person',p,'embede'),
    (-987715017,'person',p_aaben,'embede');
  -- floruit 1349-01-01..1391-12-31
  INSERT INTO assertion(id,target_type,target_id,date_raw,date_min,date_max)
    VALUES (-987715021,'fact',-987715011,'nævnt 1349-91','1349-01-01','1391-12-31');
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status)
    VALUES (-987715031,'fact',-987715011,-987715021,'afklaret');
  PERFORM pg_temp.vf_tjek(p,'1349–1391','floruit-faktum');
  -- dateret titel 1400 udvider spændet
  INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,date_min,date_max)
    VALUES (-987715022,'fact',-987715012,'syntetisk titel','1400-01-01','1400-12-31');
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status)
    VALUES (-987715032,'fact',-987715012,-987715022,'afklaret');
  PERFORM pg_temp.vf_tjek(p,'1349–1400','dateret titel');
  -- fødsel tæller ikke med i spændet (kun date_min/date_max, ingen tekst → ingen visning_foedt, så floruit vises stadig)
  INSERT INTO assertion(id,target_type,target_id,date_min,date_max)
    VALUES (-987715023,'fact',-987715013,'1300-01-01','1300-12-31');
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status)
    VALUES (-987715033,'fact',-987715013,-987715023,'afklaret');
  IF (SELECT visning_foedt FROM person WHERE id=p) IS NOT NULL THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-floruit fødsel: fixturen forventede visning_foedt NULL';
  END IF;
  PERFORM pg_temp.vf_tjek(p,'1349–1400','fødsel påvirker ikke');
  -- påstand med kun date_raw ignoreres
  INSERT INTO assertion(id,target_type,target_id,date_raw) VALUES (-987715024,'fact',-987715014,'1500');
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status)
    VALUES (-987715034,'fact',-987715014,-987715024,'afklaret');
  PERFORM pg_temp.vf_tjek(p,'1349–1400','kun date_raw');
  -- ikke-valgt dateret påstand ignoreres (den valgte er udateret)
  INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst) VALUES (-987715025,'fact',-987715015,'udateret');
  INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,date_min,date_max)
    VALUES (-987715026,'fact',-987715015,'dateret','1800-01-01','1800-12-31');
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status)
    VALUES (-987715035,'fact',-987715015,-987715025,'afklaret');
  PERFORM pg_temp.vf_tjek(p,'1349–1400','ikke-valgt påstand');
  -- status<>'afklaret' ignoreres
  INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,date_min,date_max)
    VALUES (-987715027,'fact',-987715016,'omstridt','1900-01-01','1900-12-31');
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status)
    VALUES (-987715036,'fact',-987715016,-987715027,'omstridt');
  PERFORM pg_temp.vf_tjek(p,'1349–1400','status omstridt');
  -- åben ende: date_min NULL, date_max 1261-12-31 → '1261'
  INSERT INTO assertion(id,target_type,target_id,date_raw,date_max)
    VALUES (-987715028,'fact',-987715017,'før 1261','1261-12-31');
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status)
    VALUES (-987715037,'fact',-987715017,-987715028,'afklaret');
  PERFORM pg_temp.vf_tjek(p_aaben,'1261','åben ende');
  -- person uden kilder → NULL (en forældet cacheværdi ryddes)
  UPDATE person SET visning_floruit='1111' WHERE id=p_tom;
  PERFORM regen_person_visning(p_tom);
  PERFORM pg_temp.vf_tjek(p_tom,NULL,'uden kilder');
  -- omvendt interval (date_min > date_max): siden review 37 blok 3 afvist af tabel-CHECK'en assertion_dato_orden, så
  -- tilstanden kan ikke opstå (regen_person_floruit's least/greatest er nu kun et ekstra værn).
  INSERT INTO person(id,levende,privat) VALUES (-987715004,false,false);
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-987715018,'person',-987715004,'embede');
  BEGIN
    INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,date_min,date_max)
      VALUES (-987715029,'fact',-987715018,'omvendt','1400-01-01','1300-12-31');
    RAISE EXCEPTION 'FEJL: visning-floruit — et omvendt interval blev accepteret af assertion';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  PERFORM pg_temp.vf_tjek(-987715004,NULL,'omvendt interval afvist');
  RAISE NOTICE 'OK: visning-floruit spaend';
END $verify_visning_floruit_spaend$;

-- Forvent: NOTICE "OK: visning-floruit vielse".
DO $verify_visning_floruit_vielse$
DECLARE
  actor CONSTANT uuid := '19390000-0000-4000-8000-000000000715';
  a CONSTANT bigint := -987715101; b CONSTANT bigint := -987715102; fam CONSTANT bigint := -987715110;
  fv CONSTANT bigint := -987715111; a1 CONSTANT bigint := -987715121; a2 CONSTANT bigint := -987715122;
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO auth.users(id,email) VALUES (actor,'visning-floruit-db-verify@example.invalid');
  INSERT INTO profiles(id,rolle,email) VALUES (actor,'redaktion','visning-floruit-db-verify@example.invalid');
  -- a's visning_navn sættes direkte uden navn-faktum: familie- og medlemskabsstierne må ikke røre den (kun floruit).
  INSERT INTO person(id,levende,privat,visning_navn) VALUES (a,false,false,'Direkte sat'),(b,false,false,NULL);
  INSERT INTO family(id,type) VALUES (fam,'vielse');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (fam,a,'partner'),(fam,b,'partner');
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (fv,'family',fam,'vielse');
  INSERT INTO assertion(id,target_type,target_id,date_raw,date_min,date_max,uforanderlig)
    VALUES (a1,'fact',fv,'1657','1657-01-01','1657-12-31',false);
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status) VALUES (-987715131,'fact',fv,a1,'afklaret');
  PERFORM pg_temp.vf_tjek(a,'1657','vielse a'); PERFORM pg_temp.vf_tjek(b,'1657','vielse b');
  -- ny konklusion på vielsen regenererer begge via konklusions-triggeren
  INSERT INTO assertion(id,target_type,target_id,date_raw,date_min,date_max,uforanderlig)
    VALUES (a2,'fact',fv,'1658','1658-01-01','1658-12-31',false);
  UPDATE conclusion SET valgt_assertion_id=a2 WHERE id=-987715131;
  PERFORM pg_temp.vf_tjek(a,'1658','ny konklusion a'); PERFORM pg_temp.vf_tjek(b,'1658','ny konklusion b');
  -- rettelse af den valgte påstand regenererer begge via påstands-triggeren
  UPDATE assertion SET date_raw='1657', date_min='1657-01-01', date_max='1657-12-31' WHERE id=a2;
  PERFORM pg_temp.vf_tjek(a,'1657','påstand a'); PERFORM pg_temp.vf_tjek(b,'1657','påstand b');
  -- konfidens formodet/omstridt på den ene partner-række
  UPDATE family_member SET konfidens='formodet' WHERE family_id=fam AND person_id=a;
  PERFORM pg_temp.vf_tjek(a,NULL,'formodet a'); PERFORM pg_temp.vf_tjek(b,'1657','formodet b');
  UPDATE family_member SET konfidens='sikker' WHERE family_id=fam AND person_id=a;
  PERFORM pg_temp.vf_tjek(a,'1657','sikker a');
  UPDATE family_member SET konfidens='omstridt' WHERE family_id=fam AND person_id=a;
  PERFORM pg_temp.vf_tjek(a,NULL,'omstridt a');
  UPDATE family_member SET konfidens=NULL WHERE family_id=fam AND person_id=a;
  PERFORM pg_temp.vf_tjek(a,'1657','konfidens NULL a');
  -- rolle ændret fra partner, og DELETE af partner-rækken
  UPDATE family_member SET rolle='barn' WHERE family_id=fam AND person_id=a;
  PERFORM pg_temp.vf_tjek(a,NULL,'rolle barn a'); PERFORM pg_temp.vf_tjek(b,'1657','rolle barn b');
  UPDATE family_member SET rolle='partner' WHERE family_id=fam AND person_id=a;
  PERFORM pg_temp.vf_tjek(a,'1657','rolle partner a');
  DELETE FROM family_member WHERE family_id=fam AND person_id=a;
  PERFORM pg_temp.vf_tjek(a,NULL,'delete a'); PERFORM pg_temp.vf_tjek(b,'1657','delete b');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (fam,a,'partner');
  PERFORM pg_temp.vf_tjek(a,'1657','genindsat a');
  -- sletning via redaktionens RPC: først re-peg til a1, dernæst ingen påstande tilbage → konklusionen slettes
  PERFORM set_config('request.jwt.claim.sub', actor::text, true);
  PERFORM red_slet_oplysning(a2);
  PERFORM pg_temp.vf_tjek(a,'1657','re-peg a'); PERFORM pg_temp.vf_tjek(b,'1657','re-peg b');
  PERFORM red_slet_oplysning(a1);
  PERFORM pg_temp.vf_tjek(a,NULL,'slettet a'); PERFORM pg_temp.vf_tjek(b,NULL,'slettet b');
  IF (SELECT visning_navn FROM person WHERE id=a) IS DISTINCT FROM 'Direkte sat' THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-floruit vielse: familie-/medlemskabsstierne rørte visning_navn';
  END IF;
  RAISE NOTICE 'OK: visning-floruit vielse';
END $verify_visning_floruit_vielse$;

-- Forvent: NOTICE "OK: visning-floruit gdpr".
DO $verify_visning_floruit_gdpr$
DECLARE
  a CONSTANT bigint := -987715201; b CONSTANT bigint := -987715202; barn CONSTANT bigint := -987715203;
  fam CONSTANT bigint := -987715210; fv CONSTANT bigint := -987715211;
BEGIN
  -- b's visning_navn sættes direkte uden navn-faktum: offentlighedsstien må ikke røre den (kun floruit).
  INSERT INTO person(id,levende,privat,visning_navn) VALUES (a,false,false,NULL),(b,false,false,'Direkte sat'),(barn,true,false,NULL);
  INSERT INTO family(id,type) VALUES (fam,'vielse');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (fam,a,'partner'),(fam,b,'partner');
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (fv,'family',fam,'vielse');
  INSERT INTO assertion(id,target_type,target_id,date_raw,date_min,date_max) VALUES (-987715221,'fact',fv,'1657','1657-01-01','1657-12-31');
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status) VALUES (-987715231,'fact',fv,-987715221,'afklaret');
  PERFORM pg_temp.vf_tjek(a,'1657','offentlig a');
  PERFORM pg_temp.vf_offentlig(fam,true,'åben familie');
  -- et levende barn lukker familien
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (fam,barn,'barn');
  PERFORM pg_temp.vf_offentlig(fam,false,'lukket familie');
  PERFORM pg_temp.vf_tjek(a,NULL,'levende barn a'); PERFORM pg_temp.vf_tjek(b,NULL,'levende barn b');
  UPDATE person SET levende=false WHERE id=barn;
  PERFORM pg_temp.vf_tjek(a,'1657','barn afdødt a'); PERFORM pg_temp.vf_tjek(b,'1657','barn afdødt b');
  UPDATE person SET privat=true WHERE id=barn;
  PERFORM pg_temp.vf_tjek(a,NULL,'privat a'); PERFORM pg_temp.vf_tjek(b,NULL,'privat b');
  UPDATE person SET privat=false WHERE id=barn;
  PERFORM pg_temp.vf_tjek(a,'1657','ikke privat a');
  UPDATE person SET staged=true WHERE id=barn;
  PERFORM pg_temp.vf_tjek(a,NULL,'staged a'); PERFORM pg_temp.vf_tjek(b,NULL,'staged b');
  UPDATE person SET staged=false WHERE id=barn;
  PERFORM pg_temp.vf_tjek(a,'1657','ikke staged a');
  -- levende igen, dernæst barnets række slettet → familien er offentlig igen
  UPDATE person SET levende=true WHERE id=barn;
  PERFORM pg_temp.vf_tjek(a,NULL,'levende igen a');
  DELETE FROM family_member WHERE family_id=fam AND person_id=barn;
  PERFORM pg_temp.vf_tjek(a,'1657','barn slettet a'); PERFORM pg_temp.vf_tjek(b,'1657','barn slettet b');
  PERFORM pg_temp.vf_offentlig(fam,true,'genåbnet familie');
  -- levende IS NULL (ukendt) lukker familien (fail-closed)
  INSERT INTO person(id,levende,privat) VALUES (-987715204,NULL,false);
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (fam,-987715204,'barn');
  PERFORM pg_temp.vf_offentlig(fam,false,'levende ukendt');
  PERFORM pg_temp.vf_tjek(a,NULL,'levende ukendt a'); PERFORM pg_temp.vf_tjek(b,NULL,'levende ukendt b');
  UPDATE person SET levende=false WHERE id=-987715204;
  PERFORM pg_temp.vf_tjek(a,'1657','levende afklaret a'); PERFORM pg_temp.vf_tjek(b,'1657','levende afklaret b');
  IF (SELECT visning_navn FROM person WHERE id=b) IS DISTINCT FROM 'Direkte sat' THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-floruit gdpr: offentlighedsstien rørte visning_navn';
  END IF;
  RAISE NOTICE 'OK: visning-floruit gdpr';
END $verify_visning_floruit_gdpr$;

-- Forvent: NOTICE "OK: visning-floruit flyt". Rækker flyttet mellem familier (family_id) og en partner udskiftet
-- (person_id): både gammel og ny familie og den flyttede/udskiftede person ender korrekt.
DO $verify_visning_floruit_flyt$
DECLARE
  a CONSTANT bigint := -987715401; b CONSTANT bigint := -987715402; c CONSTANT bigint := -987715403;
  e CONSTANT bigint := -987715404; barn CONSTANT bigint := -987715405;
  fam1 CONSTANT bigint := -987715410; fam2 CONSTANT bigint := -987715420;
BEGIN
  INSERT INTO person(id,levende,privat) VALUES (a,false,false),(b,false,false),(c,false,false),(e,false,false),(barn,true,false);
  INSERT INTO family(id,type) VALUES (fam1,'vielse'),(fam2,'vielse');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (fam1,a,'partner'),(fam1,b,'partner'),(fam2,c,'partner');
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-987715411,'family',fam1,'vielse'),(-987715421,'family',fam2,'vielse');
  INSERT INTO assertion(id,target_type,target_id,date_raw,date_min,date_max) VALUES
    (-987715412,'fact',-987715411,'1657','1657-01-01','1657-12-31'),(-987715422,'fact',-987715421,'1700','1700-01-01','1700-12-31');
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status) VALUES
    (-987715413,'fact',-987715411,-987715412,'afklaret'),(-987715423,'fact',-987715421,-987715422,'afklaret');
  PERFORM pg_temp.vf_tjek(a,'1657','start a'); PERFORM pg_temp.vf_tjek(c,'1700','start c');
  -- et levende barn flyttes fra fam1 til fam2: fam1 åbner, fam2 lukker
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (fam1,barn,'barn');
  PERFORM pg_temp.vf_tjek(a,NULL,'barn i fam1 a'); PERFORM pg_temp.vf_tjek(b,NULL,'barn i fam1 b');
  UPDATE family_member SET family_id=fam2 WHERE family_id=fam1 AND person_id=barn;
  PERFORM pg_temp.vf_tjek(a,'1657','barn flyttet a'); PERFORM pg_temp.vf_tjek(b,'1657','barn flyttet b');
  PERFORM pg_temp.vf_tjek(c,NULL,'barn flyttet c');
  DELETE FROM family_member WHERE family_id=fam2 AND person_id=barn;
  PERFORM pg_temp.vf_tjek(c,'1700','barn væk c');
  -- partneren a flyttes fra fam1 til fam2
  UPDATE family_member SET family_id=fam2 WHERE family_id=fam1 AND person_id=a;
  PERFORM pg_temp.vf_tjek(a,'1700','partner flyttet a'); PERFORM pg_temp.vf_tjek(b,'1657','partner flyttet b');
  PERFORM pg_temp.vf_tjek(c,'1700','partner flyttet c');
  -- partneren c udskiftes med e i fam2
  UPDATE family_member SET person_id=e WHERE family_id=fam2 AND person_id=c;
  PERFORM pg_temp.vf_tjek(c,NULL,'udskiftet c'); PERFORM pg_temp.vf_tjek(e,'1700','udskiftet e');
  PERFORM pg_temp.vf_tjek(a,'1700','udskiftet a');
  RAISE NOTICE 'OK: visning-floruit flyt';
END $verify_visning_floruit_flyt$;

-- Forvent: NOTICE "OK: visning-floruit livsdatoer". Projektejerens afgørelse 19/11: har personen livsdatoer
-- (ikke-tom visning_foedt eller visning_doed), er visning_floruit NULL.
DO $verify_visning_floruit_livsdatoer$
DECLARE p CONSTANT bigint := -987715301;
BEGIN
  INSERT INTO person(id,levende,privat) VALUES (p,false,false);
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES
    (-987715311,'person',p,'fødsel'),(-987715312,'person',p,'floruit'),(-987715313,'person',p,'død');
  INSERT INTO assertion(id,target_type,target_id,date_raw,date_min,date_max) VALUES
    (-987715321,'fact',-987715311,'1600','1600-01-01','1600-12-31'),
    (-987715322,'fact',-987715312,'1620-30','1620-01-01','1630-12-31'),
    (-987715323,'fact',-987715313,'1650','1650-01-01','1650-12-31');
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status) VALUES
    (-987715331,'fact',-987715311,-987715321,'afklaret'),(-987715332,'fact',-987715312,-987715322,'afklaret');
  IF (SELECT visning_foedt FROM person WHERE id=p) IS DISTINCT FROM '1600' THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-floruit livsdatoer: visning_foedt blev ikke sat';
  END IF;
  PERFORM pg_temp.vf_tjek(p,NULL,'med fødsel');
  -- fødselskonklusionen trækkes tilbage → ingen livsdatoer → spændet vises
  UPDATE conclusion SET status='tilbagetrukket' WHERE id=-987715331;
  IF (SELECT visning_foedt FROM person WHERE id=p) IS NOT NULL THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-floruit livsdatoer: visning_foedt blev ikke ryddet';
  END IF;
  PERFORM pg_temp.vf_tjek(p,'1620–1630','fødsel tilbagetrukket');
  -- død alene er også livsdatoer
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status)
    VALUES (-987715333,'fact',-987715313,-987715323,'afklaret');
  PERFORM pg_temp.vf_tjek(p,NULL,'med død');
  RAISE NOTICE 'OK: visning-floruit livsdatoer';
END $verify_visning_floruit_livsdatoer$;
ROLLBACK;


-- ===== visning-cache-regler (issue #396): titel- og datoregel i regen_person_visning =====
-- Titel: adelstitlen vinder over embeder; uden adelstitel den første i bogens orden (laveste fact.id) — uanset
-- indsættelses- og alfabetisk orden. Fødsel/død: kun date_raw; en udateret tekst (»ung«) er ingen livsdato.
-- Hele fixturen rulles tilbage. Forvent: NOTICE "OK: visning-cache-regler".
BEGIN;
DO $verify_visning_cache_regler$
DECLARE
  p_adel CONSTANT bigint := -987716001; p_embede CONSTANT bigint := -987716002; p_ung CONSTANT bigint := -987716003;
  v text;
BEGIN
  INSERT INTO person(id,levende,privat) VALUES (p_adel,false,false),(p_embede,false,false),(p_ung,false,false);
  -- p_adel: »kammerherre« (fact -987716013, laveste id) og »Greve« (-987716011); konklusionerne indsættes i
  -- omvendt orden, og »kammerherre« er alfabetisk størst — den gamle max()-regel valgte den.
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES
    (-987716013,'person',p_adel,'titel'),(-987716011,'person',p_adel,'titel'),
    (-987716012,'person',p_embede,'titel'),(-987716014,'person',p_embede,'titel'),
    (-987716015,'person',p_ung,'død'),(-987716016,'person',p_ung,'fødsel'),(-987716017,'person',p_ung,'floruit');
  INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst) VALUES
    (-987716021,'fact',-987716011,'Greve'),(-987716023,'fact',-987716013,'kammerherre'),
    (-987716022,'fact',-987716012,'Sekltnt.'),(-987716024,'fact',-987716014,'Fændrik ved Livregimentet'),
    (-987716025,'fact',-987716015,'ung'),(-987716026,'fact',-987716016,'lille');
  INSERT INTO assertion(id,target_type,target_id,date_raw,date_min,date_max) VALUES
    (-987716027,'fact',-987716017,'nævnt 1620','1620-01-01','1620-12-31');
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status) VALUES
    (-987716031,'fact',-987716011,-987716021,'afklaret'),(-987716033,'fact',-987716013,-987716023,'afklaret'),
    (-987716034,'fact',-987716014,-987716024,'afklaret'),(-987716032,'fact',-987716012,-987716022,'afklaret'),
    (-987716035,'fact',-987716015,-987716025,'afklaret'),(-987716036,'fact',-987716016,-987716026,'afklaret'),
    (-987716037,'fact',-987716017,-987716027,'afklaret');
  -- Cachen skrevet af triggerne; en eksplicit regen skal give det samme.
  UPDATE person SET visning_titel='forældet', visning_doed='forældet', visning_foedt='forældet'
    WHERE id IN (p_adel,p_embede,p_ung);
  PERFORM regen_person_visning(p_adel); PERFORM regen_person_visning(p_embede); PERFORM regen_person_visning(p_ung);
  SELECT visning_titel INTO v FROM person WHERE id=p_adel;
  IF v IS DISTINCT FROM 'Greve' THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-cache-regler: adelstitel forventede Greve, fik %', v;
  END IF;
  -- »Fændrik …« har laveste fact.id (-987716014 < -987716012) og vinder over den alfabetisk større »Sekltnt.«.
  SELECT visning_titel INTO v FROM person WHERE id=p_embede;
  IF v IS DISTINCT FROM 'Fændrik ved Livregimentet' THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-cache-regler: første titel forventede Fændrik ved Livregimentet, fik %', v;
  END IF;
  -- Adelstitlen matches uden hensyn til store bogstaver og omgivende mellemrum.
  UPDATE assertion SET vaerdi_tekst=' GREVE ' WHERE id=-987716021;
  PERFORM regen_person_visning(p_adel);
  IF (SELECT visning_titel FROM person WHERE id=p_adel) IS DISTINCT FROM ' GREVE ' THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-cache-regler: adelstitel matchede ikke uden hensyn til form';
  END IF;
  IF (SELECT row(visning_doed, visning_foedt) FROM person WHERE id=p_ung) IS DISTINCT FROM row(NULL::text, NULL::text) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-cache-regler: udateret død/fødsel gav livsdato (%/%)',
      (SELECT visning_doed FROM person WHERE id=p_ung), (SELECT visning_foedt FROM person WHERE id=p_ung);
  END IF;
  -- Uden livsdatoer vises floruit stadig.
  IF (SELECT visning_floruit FROM person WHERE id=p_ung) IS DISTINCT FROM '1620' THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-cache-regler: floruit forventede 1620, fik %',
      (SELECT visning_floruit FROM person WHERE id=p_ung);
  END IF;
  -- En død med datotekst vises stadig.
  UPDATE assertion SET date_raw='1650' WHERE id=-987716025;
  PERFORM regen_person_visning(p_ung);
  IF (SELECT visning_doed FROM person WHERE id=p_ung) IS DISTINCT FROM '1650' THEN
    RAISE EXCEPTION 'VERIFY_FAILED: visning-cache-regler: død med date_raw blev ikke vist';
  END IF;
  RAISE NOTICE 'OK: visning-cache-regler';
END $verify_visning_cache_regler$;
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
  -- Task 8a: lokale forældre før polymorfe testbørn; rulles tilbage med scenariet.
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO public.person(id,levende,privat) VALUES (-99,false,false) ON CONFLICT (id) DO NOTHING;
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
                                         'visning_efternavn','visning_fuldt_navn','visning_floruit']) THEN
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
  -- Task 8a: lokale forældre før polymorfe testbørn; rulles tilbage med scenariet.
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO public.person(id,levende,privat) VALUES (1,false,false) ON CONFLICT (id) DO NOTHING;
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
  -- Review 37 P11: red_opret_person opretter en privat person, og kun en offentlig kan slettes, så det kan fortrydes.
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_set_privat(v_pid,false);
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
  -- Task 8a: lokale forældre før polymorfe testbørn; rulles tilbage med scenariet.
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO public.person(id,levende,privat) VALUES (1,false,false) ON CONFLICT (id) DO NOTHING;
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
  -- Task 8a: lokale forældre før polymorfe testbørn; rulles tilbage med scenariet.
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO public.person(id,levende,privat) VALUES (1,false,false) ON CONFLICT (id) DO NOTHING;
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
  -- Task 8a: lokale forældre før polymorfe testbørn; rulles tilbage med scenariet.
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO public.person(id,levende,privat) VALUES (-999904,false,false) ON CONFLICT (id) DO NOTHING;
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
-- Rollen er en gyldig barn-subtype (family_member_rolle_chk, review 37 blok 3), som ikke rammer fødselsfamilie-reglen.
BEGIN;
DO $$
DECLARE
  v_family CONSTANT bigint := -987656221;
  v_person CONSTANT bigint := -987656222;
  cur jsonb;
  pk jsonb := jsonb_build_object(
    'family_id',-987656221,'person_id',-987656222,'rolle','plejebarn');
BEGIN
  INSERT INTO family(id,type) VALUES (v_family,'ukendt');
  INSERT INTO person(id,levende,privat) VALUES (v_person,false,false);
  PERFORM _version_upsert_row('family_member',
    jsonb_build_object('family_id',v_family,'person_id',v_person,'rolle','plejebarn','ordinal',9,'konfidens','sikker'));
  cur := _version_current_row('family_member', pk);
  IF cur->>'konfidens' <> 'sikker' THEN RAISE EXCEPTION 'FEJL: composite upsert-insert virkede ikke (%)', cur; END IF;
  -- update via ON CONFLICT (samme composite-nøgle)
  PERFORM _version_upsert_row('family_member',
    jsonb_build_object('family_id',v_family,'person_id',v_person,'rolle','plejebarn','ordinal',9,'konfidens','formodet'));
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
  -- Task 8a: lokale forældre før polymorfe testbørn; rulles tilbage med scenariet.
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO public.person(id,levende,privat) VALUES (1,false,false) ON CONFLICT (id) DO NOTHING;
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

-- BEGIN-VERIFY r37b1-d2
-- ===== Review 37 D2: fortryd sammenligner kun kolonner i snapshottet =====
-- Et sæt optaget før en kolonne kom til (fx relation.kvalifikator) mangler kolonnen i foer/efter. (a) UPDATE-
-- fortrydelse lykkes og genskaber foer; den nye kolonne bevarer sin nuværende værdi. (b) En kolonne i snapshottet,
-- som er ændret siden, afvises stadig. (c) En nøgle, der ikke længere er en kolonne, springes over ved
-- genindsættelse (DELETE-inverse) i stedet for at fejle med 42703. Selvforsynende; rulles tilbage.
DO $$
DECLARE v_nid bigint; cs bigint; afvist boolean := false; r record; v_res jsonb;
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO public.person(id,levende,privat) VALUES (1,false,false) ON CONFLICT (id) DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';

  -- (a) note.privat »findes ikke« i sættets snapshot; rækken har privat=true i dag.
  INSERT INTO note(target_type,target_id,indhold,privat) VALUES ('person',1,'EFTER',true) RETURNING id INTO v_nid;
  INSERT INTO change_set(operation,summary,subjekt_synlighed) VALUES ('t','gammelt sæt','offentlig') RETURNING id INTO cs;
  INSERT INTO change_event(change_set_id,seq,tabel,row_pk,op,foer,efter)
    VALUES (cs, 1, 'note', jsonb_build_object('id',v_nid),'UPDATE',
            jsonb_build_object('id',v_nid,'target_type','person','target_id',1,'indhold','FOER'),
            jsonb_build_object('id',v_nid,'target_type','person','target_id',1,'indhold','EFTER'));
  v_res := red_fortryd_change_set(cs, false);
  SELECT * INTO r FROM note WHERE id=v_nid;
  IF r.indhold IS DISTINCT FROM 'FOER' OR r.target_type<>'person' OR r.target_id<>1 THEN
    RAISE EXCEPTION 'FEJL: D2 — rækken blev ikke genskabt til foer (indhold=%)', r.indhold; END IF;
  IF r.privat IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FEJL: D2 — kolonnen uden for snapshottet blev rørt (privat=%)', r.privat; END IF;
  IF (v_res->>'divergenser')::int <> 0 THEN
    RAISE EXCEPTION 'FEJL: D2 — fortrydelsen talte divergenser: %', v_res; END IF;

  -- (b) kontrol: indhold (i snapshottet) er ændret siden → stadig afvist uden force, rækken uberørt.
  INSERT INTO note(target_type,target_id,indhold,privat) VALUES ('person',1,'NYERE',true) RETURNING id INTO v_nid;
  INSERT INTO change_set(operation,summary,subjekt_synlighed) VALUES ('t','gammelt sæt 2','offentlig') RETURNING id INTO cs;
  INSERT INTO change_event(change_set_id,seq,tabel,row_pk,op,foer,efter)
    VALUES (cs, 1, 'note', jsonb_build_object('id',v_nid),'UPDATE',
            jsonb_build_object('id',v_nid,'target_type','person','target_id',1,'indhold','FOER'),
            jsonb_build_object('id',v_nid,'target_type','person','target_id',1,'indhold','EFTER'));
  BEGIN PERFORM red_fortryd_change_set(cs, false);
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%nyere ændring rører%' THEN afvist := true; ELSE RAISE; END IF; END;
  IF NOT afvist THEN RAISE EXCEPTION 'FEJL: D2 — en nyere ændring i en snapshot-kolonne blev ikke afvist'; END IF;
  IF (SELECT indhold FROM note WHERE id=v_nid) <> 'NYERE' THEN
    RAISE EXCEPTION 'FEJL: D2 — rækken blev rørt trods afvisning'; END IF;

  -- (c) DELETE-inverse med en droppet kolonne i snapshottet: rækken genindsættes uden den.
  v_nid := (SELECT coalesce(max(id),0)+1 FROM note);
  INSERT INTO change_set(operation,summary,subjekt_synlighed) VALUES ('t','gammelt sæt 3','offentlig') RETURNING id INTO cs;
  INSERT INTO change_event(change_set_id,seq,tabel,row_pk,op,foer,efter)
    VALUES (cs, 1, 'note', jsonb_build_object('id',v_nid),'DELETE',
            jsonb_build_object('id',v_nid,'target_type','person','target_id',1,'indhold','SLETTET',
                               'privat',false,'droppet_kolonne','x'), NULL);
  PERFORM red_fortryd_change_set(cs, false);
  IF (SELECT indhold FROM note WHERE id=v_nid) IS DISTINCT FROM 'SLETTET' THEN
    RAISE EXCEPTION 'FEJL: D2 — DELETE-inverse genindsatte ikke rækken med en droppet kolonne i snapshottet'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review37 D2 — fortryd tåler kolonner uden for snapshottet';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY r37b1-d2

-- BEGIN-VERIFY r37b1-d7
-- ===== Review 37 D7: udgavepublicering er ét ændringssæt og kan fortrydes =====
-- To stagede personer fra udgaven (én med external_id, én partner-stub i samme familie) og én staget person fra
-- en anden udgave. red_publicer_udgave skal åbne et sæt med ét person-event pr. afstaget person; fortrydelsen af
-- sættet gør begge stagede igen (projektejeren 2026-11-22). Den fremmede person røres ikke. Selvforsynende.
DO $$
DECLARE v_res jsonb; cs bigint; n_ev int;
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  INSERT INTO source(id,slags,titel,import_key) VALUES
    (-937101,'test','r37b1 D7 udgave','r37b1-d7-udgave'),(-937102,'test','r37b1 D7 anden','r37b1-d7-anden');
  INSERT INTO person(id,levende,privat,staged) VALUES
    (-937111,false,false,true),(-937112,false,false,true),(-937113,false,false,true);
  INSERT INTO person_external_id(person_id,source_id,linje,nr) VALUES (-937111,-937101,'I',1),(-937113,-937102,'I',1);
  INSERT INTO family(id) VALUES (-937121);
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (-937121,-937111,'partner'),(-937121,-937112,'partner');

  v_res := red_publicer_udgave(-937101);
  IF (v_res->>'personer_afstaget')::int <> 2 THEN RAISE EXCEPTION 'FEJL: D7 — forventede 2 afstagede, fik %', v_res; END IF;
  SELECT max(id) INTO cs FROM change_set WHERE operation='red_publicer_udgave';
  IF cs IS NULL THEN RAISE EXCEPTION 'FEJL: D7 — red_publicer_udgave åbnede intet ændringssæt'; END IF;
  SELECT count(*) INTO n_ev FROM change_event
   WHERE change_set_id=cs AND tabel='person' AND op='UPDATE' AND (efter->>'staged')::boolean IS false
     AND (foer->>'staged')::boolean AND (row_pk->>'id')::bigint IN (-937111,-937112);
  IF n_ev <> 2 THEN RAISE EXCEPTION 'FEJL: D7 — sættet har % person-events for de 2 afstagede', n_ev; END IF;
  IF EXISTS (SELECT 1 FROM person WHERE id IN (-937111,-937112) AND staged) OR NOT (SELECT staged FROM person WHERE id=-937113) THEN
    RAISE EXCEPTION 'FEJL: D7 — publiceringen afstagede forkerte personer'; END IF;

  PERFORM set_config('app.change_set_id','',true);
  v_res := red_fortryd_change_set(cs, false);
  IF (v_res->>'divergenser')::int <> 0 THEN RAISE EXCEPTION 'FEJL: D7 — fortrydelsen talte divergenser: %', v_res; END IF;
  IF (SELECT count(*) FROM person WHERE id IN (-937111,-937112,-937113) AND staged) <> 3 THEN
    RAISE EXCEPTION 'FEJL: D7 — fortrydelsen gjorde ikke udgavens personer stagede igen'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review37 D7 — udgavepublicering står i historikken og kan fortrydes';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY r37b1-d7

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
  -- Review 37 P11: red_opret_person opretter en privat person, og kun en offentlig kan slettes, så det kan fortrydes.
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_set_privat(v_pid,false);
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

-- BEGIN-VERIFY r37b1-s2
-- ===== Review 37 S2: bogmærke-INSERT er ikke et eksistens-orakel =====
-- Et medlem får samme 42501 for en levende (skjult) person og for et id, der ikke findes (før: 23503 FK-fejl,
-- der afslørede eksistensen). Redaktionen må stadig bogmærke en levende person (projektejeren 2026-11-22), og
-- medlemmet kan stadig bogmærke en offentlig person. Selvforsynende; rulles tilbage.
DO $$
DECLARE v_state text; v_ok boolean;
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO auth.users(id,email) VALUES
    ('00000000-0000-0000-0000-0000000000b1','s2-medlem@test.invalid'),
    ('00000000-0000-0000-0000-0000000000b2','s2-redaktion@test.invalid')
  ON CONFLICT (id) DO NOTHING;
  DELETE FROM profiles WHERE id='00000000-0000-0000-0000-0000000000b1';
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-0000000000b2','redaktion','s2@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  INSERT INTO person(id,levende,privat) VALUES (-937201,false,false),(-937202,true,false);
  DELETE FROM person WHERE id=-937203;

  -- Medlem: levende person → 42501
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',true);
  SET LOCAL ROLE authenticated;
  v_state := 'ingen fejl';
  BEGIN INSERT INTO bookmark(person_id) VALUES (-937202);
  EXCEPTION WHEN OTHERS THEN v_state := SQLSTATE; END;
  RESET ROLE;
  IF v_state <> '42501' THEN RAISE EXCEPTION 'FEJL: S2 — medlem bogmærkede levende person: % (forventede 42501)', v_state; END IF;

  -- Medlem: ikke-eksisterende id → samme 42501 (ikke 23503)
  SET LOCAL ROLE authenticated;
  v_state := 'ingen fejl';
  BEGIN INSERT INTO bookmark(person_id) VALUES (-937203);
  EXCEPTION WHEN OTHERS THEN v_state := SQLSTATE; END;
  RESET ROLE;
  IF v_state <> '42501' THEN RAISE EXCEPTION 'FEJL: S2 — ikke-eksisterende id gav % (forventede 42501, samme som skjult)', v_state; END IF;

  -- Medlem: offentlig person → tilladt
  SET LOCAL ROLE authenticated;
  INSERT INTO bookmark(person_id) VALUES (-937201);
  RESET ROLE;

  -- Redaktion: levende person → tilladt
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',true);
  SET LOCAL ROLE authenticated;
  INSERT INTO bookmark(person_id) VALUES (-937202);
  RESET ROLE;
  SELECT count(*)=2 INTO v_ok FROM bookmark WHERE person_id IN (-937201,-937202);
  IF NOT v_ok THEN RAISE EXCEPTION 'FEJL: S2 — forventede 2 tilladte bogmærker'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review37 S2 — bogmærke-INSERT er ikke et eksistens-orakel; redaktionen må bogmærke skjulte';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY r37b1-s2

-- BEGIN-VERIFY r37b1-y9
-- ===== Review 37 Y9: FK'er med indeks (haendelse, story, bookmark) =====
-- Hvert indeks skal findes på den rigtige tabel og have FK-kolonnen som første (eneste) nøglekolonne.
DO $$
DECLARE r record; v_mangler text[] := '{}';
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('ix_haendelse_fact_id','haendelse','fact_id'),
      ('ix_haendelse_relation_id','haendelse','relation_id'),
      ('ix_story_fact_id','story','fact_id'),
      ('ix_story_relation_id','story','relation_id'),
      ('ix_story_historical_event_id','story','historical_event_id'),
      ('ix_bookmark_person_id','bookmark','person_id')) v(ix,tabel,kol) LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_index i
        JOIN pg_class ic ON ic.oid=i.indexrelid
        JOIN pg_class tc ON tc.oid=i.indrelid
        JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=i.indkey[0]
       WHERE ic.relnamespace='public'::regnamespace AND ic.relname=r.ix
         AND tc.relname=r.tabel AND a.attname=r.kol AND i.indnkeyatts=1 AND i.indisvalid) THEN
      v_mangler := v_mangler || r.ix;
    END IF;
  END LOOP;
  IF cardinality(v_mangler) > 0 THEN
    RAISE EXCEPTION 'FEJL: Y9 — FK-indeks mangler eller er forkerte: %', v_mangler; END IF;
  RAISE NOTICE 'OK: review37 Y9 — seks FK-indeks på haendelse, story og bookmark';
END $$;
-- END-VERIFY r37b1-y9

-- BEGIN-VERIFY r37b2-d1
-- ===== Review 37 D1 (+ D12): slægtsnavnet kommer også fra linjemedlemskabet =====
-- (a) En person uden linjekode får visning_efternavn, når et medlemskab indsættes (som promotionen gør); (b) en ændring
-- af linjens slaegtsnavn regenererer medlemmet; (c) reversal (red_reverse_placement_membership) gør efternavnet NULL
-- igen. (d) Linjekode + medlemskab med to forskellige navne giver karantæne som før. (e) D12: ændret kode og sletning af
-- linjen regenererer linjekodens personer. Selvforsynende; rulles tilbage.
DO $$
DECLARE v_e text; v_f text;
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  INSERT INTO source(id,slags,titel,import_key) VALUES (-937201,'test','r37b2 D1','r37b2-d1');
  INSERT INTO lineage(id,source_id,kode,navn,slaegtsnavn) VALUES
    (-937211,-937201,'R37B2D1','r37b2 D1-linje','R37b2slaegt'),
    (-937212,-937201,'R37B2D1B','r37b2 D1-anden','R37b2anden');
  INSERT INTO person(id,levende,privat) VALUES (-937221,false,false),(-937222,false,false),(-937223,false,false);
  PERFORM red_upsert_fakta('person',-937221,'navn','Conrad');
  PERFORM red_upsert_fakta('person',-937222,'navn','Bodil');
  PERFORM red_upsert_fakta('person',-937223,'navn','Cecilie');
  PERFORM set_config('app.change_set_id','',true);

  -- (a) medlemskab uden linjekode.
  INSERT INTO person_lineage_membership(person_id,lineage_id,role,source_basis)
    VALUES (-937221,-937211,'member','{"rule_version":"placement-membership-v1","source_id":"-937201"}');
  SELECT visning_efternavn, visning_fuldt_navn INTO v_e, v_f FROM person WHERE id=-937221;
  IF v_e IS DISTINCT FROM 'R37b2slaegt' OR v_f IS DISTINCT FROM 'Conrad R37b2slaegt' THEN
    RAISE EXCEPTION 'FEJL: D1 — medlemskab gav intet slægtsnavn (efternavn=%, fuldt=%)', v_e, v_f; END IF;
  -- (b) linjens navn ændres.
  UPDATE lineage SET slaegtsnavn='R37b2nyt' WHERE id=-937211;
  IF (SELECT visning_efternavn FROM person WHERE id=-937221) IS DISTINCT FROM 'R37b2nyt' THEN
    RAISE EXCEPTION 'FEJL: D1 — ændret slaegtsnavn regenererede ikke medlemmet'; END IF;
  -- (c) reversal.
  PERFORM red_reverse_placement_membership(-937221,-937211,'r37b2 D1 test');
  SELECT visning_efternavn, visning_fuldt_navn INTO v_e, v_f FROM person WHERE id=-937221;
  IF v_e IS NOT NULL OR v_f IS DISTINCT FROM 'Conrad' THEN
    RAISE EXCEPTION 'FEJL: D1 — efternavnet blev stående efter reversal (efternavn=%, fuldt=%)', v_e, v_f; END IF;

  -- (d) linjekode (R37b2nyt) + medlemskab på en linje med et andet navn → karantæne, intet efternavn.
  INSERT INTO person_external_id(person_id,source_id,linje,nr) VALUES (-937223,-937201,'R37B2D1',2);
  IF (SELECT visning_efternavn FROM person WHERE id=-937223) IS DISTINCT FROM 'R37b2nyt' THEN
    RAISE EXCEPTION 'FEJL: D1 — linjekoden gav ikke slægtsnavnet'; END IF;
  INSERT INTO person_lineage_membership(person_id,lineage_id,role,source_basis)
    VALUES (-937223,-937212,'member','{"rule_version":"placement-membership-v1","source_id":"-937201"}');
  IF (SELECT visning_efternavn FROM person WHERE id=-937223) IS NOT NULL
     OR NOT EXISTS (SELECT 1 FROM slaegtsnavn_karantaene WHERE person_id=-937223 AND n_distinct=2) THEN
    RAISE EXCEPTION 'FEJL: D1 — to forskellige navne fra linjekode og medlemskab gav ikke karantæne'; END IF;
  DELETE FROM person_lineage_membership WHERE person_id=-937223;
  IF (SELECT visning_efternavn FROM person WHERE id=-937223) IS DISTINCT FROM 'R37b2nyt'
     OR EXISTS (SELECT 1 FROM slaegtsnavn_karantaene WHERE person_id=-937223) THEN
    RAISE EXCEPTION 'FEJL: D1 — sletning af medlemskabet hævede ikke karantænen'; END IF;

  -- (e) D12: kodeskift og sletning af linjen.
  INSERT INTO person_external_id(person_id,source_id,linje,nr) VALUES (-937222,-937201,'R37B2D1',1);
  UPDATE lineage SET kode='R37B2D1X' WHERE id=-937211;
  IF (SELECT visning_efternavn FROM person WHERE id=-937222) IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: D12 — ændret linjekode regenererede ikke linjekodens personer'; END IF;
  UPDATE lineage SET kode='R37B2D1' WHERE id=-937211;
  IF (SELECT visning_efternavn FROM person WHERE id=-937222) IS DISTINCT FROM 'R37b2nyt' THEN
    RAISE EXCEPTION 'FEJL: D12 — personerne på den nye linjekode blev ikke regenereret'; END IF;
  DELETE FROM lineage WHERE id=-937211;
  IF (SELECT visning_efternavn FROM person WHERE id=-937222) IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: D12 — sletning af linjen regenererede ikke linjekodens personer'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review37 D1 — slægtsnavn fra linjemedlemskab, D12 linjetrigger';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY r37b2-d1

-- BEGIN-VERIFY r37b2-d3
-- ===== Review 37 D3: »Ret navn/titel« rammer den viste oplysning; navn/fødsel/død vises i bogens orden =====
-- (a) To afklarede navne: visningen er den første i bogens orden (ikke alfabetisk max()), og red_upsert_fakta('navn')
-- retter netop det faktum. (b) Titel: en ikke-adelig titel først, så »Greve«: red_upsert_fakta('titel') retter Greve-
-- faktummet. (c) Et tilbagetrukket navn før det viste genaktiveres ikke. (d) En tilbagetrukket forældre_ukendt-
-- markering genaktiveres stadig på samme faktum. (e) En udateret død (»ung«) før en dateret skjuler ikke datoen.
-- Selvforsynende; rulles tilbage.
DO $$
DECLARE v_f1 bigint; v_f2 bigint; v_res jsonb;
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  INSERT INTO person(id,levende,privat) VALUES (-937301,false,false),(-937302,false,false),(-937303,false,false),
    (-937304,false,false),(-937305,false,false);

  -- (a) navn: Anna (bogens første) og Bodil (alfabetisk størst, max() viste den).
  v_f1 := (red_opret_fakta('person',-937301,'navn','Anna')->>'fact_id')::bigint;
  v_f2 := (red_opret_fakta('person',-937301,'navn','Bodil')->>'fact_id')::bigint;
  IF (SELECT visning_navn FROM person WHERE id=-937301) IS DISTINCT FROM 'Anna' THEN
    RAISE EXCEPTION 'FEJL: D3 — visningen viser ikke det første navn i bogens orden (%)',
      (SELECT visning_navn FROM person WHERE id=-937301); END IF;
  v_res := red_upsert_fakta('person',-937301,'navn','Annette');
  IF (v_res->>'fact_id')::bigint IS DISTINCT FROM v_f1
     OR (SELECT visning_navn FROM person WHERE id=-937301) IS DISTINCT FROM 'Annette' THEN
    RAISE EXCEPTION 'FEJL: D3 — red_upsert_fakta(navn) ramte fakta % i stedet for det viste %', v_res->>'fact_id', v_f1; END IF;

  -- (b) titel: Kammerherre først, så Greve (vist).
  v_f1 := (red_opret_fakta('person',-937302,'titel','Kammerherre')->>'fact_id')::bigint;
  v_f2 := (red_opret_fakta('person',-937302,'titel','Greve')->>'fact_id')::bigint;
  IF (SELECT visning_titel FROM person WHERE id=-937302) IS DISTINCT FROM 'Greve' THEN
    RAISE EXCEPTION 'FEJL: D3 — adelstitlen vises ikke'; END IF;
  v_res := red_upsert_fakta('person',-937302,'titel','Lensgreve');
  IF (v_res->>'fact_id')::bigint IS DISTINCT FROM v_f2
     OR (SELECT a.vaerdi_tekst FROM conclusion c JOIN assertion a ON a.id=c.valgt_assertion_id
          WHERE c.target_type='fact' AND c.target_id=v_f2) IS DISTINCT FROM 'Lensgreve'
     OR (SELECT visning_titel FROM person WHERE id=-937302) IS DISTINCT FROM 'Lensgreve' THEN
    RAISE EXCEPTION 'FEJL: D3 — red_upsert_fakta(titel) ramte fakta % i stedet for Greve-faktummet %', v_res->>'fact_id', v_f2; END IF;

  -- (c) et tilbagetrukket navn før det viste.
  v_f1 := (red_opret_fakta('person',-937303,'navn','Gammel')->>'fact_id')::bigint;
  PERFORM red_tilbagetraek_fakta(v_f1);
  v_f2 := (red_opret_fakta('person',-937303,'navn','Anna')->>'fact_id')::bigint;
  v_res := red_upsert_fakta('person',-937303,'navn','Anne');
  IF (v_res->>'fact_id')::bigint IS DISTINCT FROM v_f2
     OR (SELECT status FROM conclusion WHERE target_type='fact' AND target_id=v_f1) IS DISTINCT FROM 'tilbagetrukket'
     OR (SELECT visning_navn FROM person WHERE id=-937303) IS DISTINCT FROM 'Anne' THEN
    RAISE EXCEPTION 'FEJL: D3 — red_upsert_fakta(navn) genaktiverede det tilbagetrukne faktum % i stedet for det viste %',
      v_res->>'fact_id', v_f2; END IF;

  -- (d) forældre_ukendt: markér, tilbagetræk, markér igen → samme faktum, afklaret.
  v_f1 := (red_upsert_fakta('person',-937304,'forældre_ukendt','ukendt')->>'fact_id')::bigint;
  PERFORM red_tilbagetraek_fakta(v_f1);
  v_res := red_upsert_fakta('person',-937304,'forældre_ukendt','ukendt');
  IF (v_res->>'fact_id')::bigint IS DISTINCT FROM v_f1
     OR (SELECT count(*) FROM fact WHERE subjekt_type='person' AND subjekt_id=-937304) <> 1
     OR (SELECT status FROM conclusion WHERE target_type='fact' AND target_id=v_f1) IS DISTINCT FROM 'afklaret' THEN
    RAISE EXCEPTION 'FEJL: D3 — forældre_ukendt blev ikke genaktiveret på samme faktum (%)', v_res; END IF;

  -- (e) død: »ung« (udateret) før en dateret død.
  PERFORM red_opret_fakta('person',-937305,'død','ung');
  PERFORM red_opret_fakta('person',-937305,'død','2. okt. 1859', p_date_raw => '2. okt. 1859');
  IF (SELECT visning_doed FROM person WHERE id=-937305) IS DISTINCT FROM '2. okt. 1859' THEN
    RAISE EXCEPTION 'FEJL: D3 — en udateret død skjulte datoen (%)', (SELECT visning_doed FROM person WHERE id=-937305); END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review37 D3 — visning og »Ret« følger samme faktum';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY r37b2-d3

-- BEGIN-VERIFY r37b2-d5
-- ===== Review 37 D5 (RPC-delen): redigerings-RPC'erne afviser date_min > date_max =====
-- red_upsert_fakta, red_opret_fakta og red_tilfoej_oplysning kaster DATO_INTERVAL_OMVENDT (22023) uden at åbne et
-- ændringssæt; et lige interval (min = max) og åbne grænser er stadig tilladt. Selvforsynende; rulles tilbage.
DO $$
DECLARE v_fact bigint; n_cs bigint; v_rpc text; v_ok boolean; v_state text; v_msg text;
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  INSERT INTO person(id,levende,privat) VALUES (-937401,false,false);
  v_fact := (red_opret_fakta('person',-937401,'fødsel','1850', '1850-01-01', '1850-01-01', NULL, '1850')->>'fact_id')::bigint;
  PERFORM red_upsert_fakta('person',-937401,'død','1900', NULL, '1900-12-31', NULL, '1900');
  PERFORM set_config('app.change_set_id','',true);
  SELECT count(*) INTO n_cs FROM change_set;
  FOREACH v_rpc IN ARRAY ARRAY['red_upsert_fakta','red_opret_fakta','red_tilfoej_oplysning'] LOOP
    v_ok := false;
    BEGIN
      IF v_rpc = 'red_upsert_fakta' THEN
        PERFORM red_upsert_fakta('person',-937401,'fødsel','1851', '1851-12-31', '1851-01-01', NULL, '1851');
      ELSIF v_rpc = 'red_opret_fakta' THEN
        PERFORM red_opret_fakta('person',-937401,'fødsel','1851', '1851-12-31', '1851-01-01', NULL, '1851');
      ELSE
        PERFORM red_tilfoej_oplysning(v_fact,'1851', '1851-12-31', '1851-01-01', NULL, '1851');
      END IF;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      IF v_state = '22023' AND v_msg = 'DATO_INTERVAL_OMVENDT' THEN v_ok := true; ELSE RAISE; END IF;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'FEJL: D5 — % accepterede et omvendt datointerval', v_rpc; END IF;
    PERFORM set_config('app.change_set_id','',true);
  END LOOP;
  IF (SELECT count(*) FROM change_set) <> n_cs THEN
    RAISE EXCEPTION 'FEJL: D5 — en afvist skrivning åbnede et ændringssæt'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review37 D5 — omvendt datointerval afvises i tre redigerings-RPC''er';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY r37b2-d5

-- BEGIN-VERIFY r37b3-s4
-- ===== Review 37 S4: et billede afbilder person (person → media) eller gods/våben/linje/familie/sted (media → …) =====
-- Tabel-CHECK'en relation_afbildet_kanonisk afviser enhver anden retning og enhver stavemåde af 'afbildet' end den
-- eksakte (billed-gaten sammenligner eksakt). red_relation og red_tilfoej_relation afviser med AFBILDET_RETNING_UGYLDIG
-- (22023) uden at åbne et ændringssæt. Alle seks tilladte retninger accepteres. Selvforsynende; rulles tilbage.
DO $$
DECLARE v_t text; v_n_cs bigint; v_state text; v_msg text; v_ok boolean;
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  INSERT INTO person(id,levende,privat) VALUES (-937601,false,false);
  INSERT INTO family(id,type) VALUES (-937611,'vielse');
  INSERT INTO media(id,slags) VALUES (-937621,'portræt'),(-937622,'portræt');
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-937631,'person',-937601,'embede');
  -- Stavemåder, der ville gå uden om gaten, og retninger uden for listen: tabel-CHECK'en.
  FOREACH v_t IN ARRAY ARRAY['Afbildet',' afbildet','AFBILDET '] LOOP
    v_ok := false;
    BEGIN
      INSERT INTO relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('person',-937601,'media',-937621,v_t);
    EXCEPTION WHEN check_violation THEN v_ok := true;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'FEJL: S4 — relation accepterede rollen «%» (relation_afbildet_kanonisk mangler)', v_t; END IF;
  END LOOP;
  v_ok := false;
  BEGIN
    INSERT INTO relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('media',-937621,'fact',-937631,'afbildet');
  EXCEPTION WHEN check_violation THEN v_ok := true;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'FEJL: S4 — relation accepterede media → fact som afbildet'; END IF;
  -- Redigerings-RPC'erne: læsbar fejl før ændringssættet.
  SELECT count(*) INTO v_n_cs FROM change_set;
  FOREACH v_t IN ARRAY ARRAY['media→fact','media→organisation','Afbildet','person→estate'] LOOP
    v_ok := false;
    BEGIN
      IF v_t = 'media→fact' THEN PERFORM red_relation('media',-937621,'fact',-937631,'afbildet');
      ELSIF v_t = 'media→organisation' THEN PERFORM red_relation('media',-937621,'organisation',-937641,'afbildet');
      ELSIF v_t = 'Afbildet' THEN PERFORM red_relation('person',-937601,'media',-937621,'Afbildet');
      ELSE PERFORM red_tilfoej_relation(-937601,'estate',-937642,' afbildet');
      END IF;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      IF v_state = '22023' AND v_msg LIKE 'AFBILDET_RETNING_UGYLDIG:%' THEN v_ok := true;
      ELSIF v_state = '23514' THEN v_ok := false;
      ELSE RAISE; END IF;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'FEJL: S4 — % blev ikke afvist med AFBILDET_RETNING_UGYLDIG', v_t; END IF;
    PERFORM set_config('app.change_set_id','',true);
  END LOOP;
  IF (SELECT count(*) FROM change_set) <> v_n_cs THEN
    RAISE EXCEPTION 'FEJL: S4 — en afvist afbildning åbnede et ændringssæt'; END IF;
  -- De seks tilladte retninger.
  PERFORM red_relation('person',-937601,'media',-937621,'afbildet');
  FOREACH v_t IN ARRAY ARRAY['estate','coat_of_arms','lineage','family','place'] LOOP
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_relation('media',-937622,v_t,CASE WHEN v_t='family' THEN -937611 ELSE -937650 END,'afbildet');
  END LOOP;
  IF (SELECT count(*) FROM relation WHERE rolle='afbildet' AND -937621 IN (subjekt_id,objekt_id)) <> 1
     OR (SELECT count(*) FROM relation WHERE rolle='afbildet' AND subjekt_type='media' AND subjekt_id=-937622) <> 5 THEN
    RAISE EXCEPTION 'FEJL: S4 — en tilladt retning blev ikke oprettet'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review37 S4 — afbildet kun i de seks retninger, eksakt stavet';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY r37b3-s4

-- BEGIN-VERIFY r37b3-gate
-- ===== Review 37 S4: billed-gaten følger familiens synlighed =====
-- media_afbilder_skjult er sand for et billede af en familie, der ikke er offentlig (et levende eller privat medlem);
-- media_afbilder_privat for en familie med et privat medlem. Et billede af en offentlig familie er synligt. S3
-- (2026-11-22): et billede af en familie UDEN medlemmer er skjult, fordi family_offentlig er falsk for den.
-- Kaldt som ejer (begge er lukket for klientroller); gæst/medlem-matricen står i tests/sql/test-review37-b3-gate.sql.
DO $$
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO person(id,levende,privat) VALUES (-937701,true,false),(-937702,false,false),(-937703,false,true),(-937704,false,false);
  INSERT INTO family(id,type) VALUES (-937711,'vielse'),(-937712,'vielse'),(-937713,'vielse'),(-937714,'vielse');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES
    (-937711,-937701,'partner'),(-937711,-937702,'partner'),   -- levende medlem
    (-937712,-937703,'partner'),(-937712,-937702,'partner'),   -- privat (afdødt) medlem
    (-937713,-937702,'partner'),(-937713,-937704,'partner');   -- offentlig; -937714 har ingen medlemmer
  INSERT INTO media(id,slags,maa_publiceres,upload_status) VALUES
    (-937721,'portræt',true,'klar'),(-937722,'portræt',true,'klar'),(-937723,'portræt',true,'klar'),(-937724,'portræt',true,'klar');
  INSERT INTO relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES
    ('media',-937721,'family',-937711,'afbildet'),('media',-937722,'family',-937712,'afbildet'),
    ('media',-937723,'family',-937713,'afbildet'),('media',-937724,'family',-937714,'afbildet');
  IF NOT media_afbilder_skjult(-937721) OR media_synlig_anon(-937721) THEN
    RAISE EXCEPTION 'FEJL: gate — billedet af en familie med et levende medlem er ikke skjult'; END IF;
  IF NOT media_afbilder_skjult(-937722) OR NOT media_afbilder_privat(-937722) OR media_synlig_auth(-937722) THEN
    RAISE EXCEPTION 'FEJL: gate — billedet af en familie med et privat medlem er ikke skjult (skjult=%, privat=%)',
      media_afbilder_skjult(-937722), media_afbilder_privat(-937722); END IF;
  IF media_afbilder_privat(-937721) THEN
    RAISE EXCEPTION 'FEJL: gate — media_afbilder_privat er sand for en familie uden privat medlem'; END IF;
  IF media_afbilder_skjult(-937723) OR NOT media_synlig_anon(-937723) THEN
    RAISE EXCEPTION 'FEJL: gate — billedet af en offentlig familie er skjult'; END IF;
  IF NOT media_afbilder_skjult(-937724) OR media_synlig_anon(-937724) THEN
    RAISE EXCEPTION 'FEJL: gate — S3: billedet af en medlemsløs familie er ikke skjult'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review37 S4 gate — billedet følger familiens synlighed (medlemsløs familie: skjult, S3)';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY r37b3-gate

-- BEGIN-VERIFY r37s3
-- ===== Review 37 S3: en familie uden medlemmer er ikke offentlig =====
-- family_offentlig er falsk for en familie uden medlemmer og for et ikke-eksisterende id; en familie med kun afdøde,
-- offentlige medlemmer er offentlig; et levende medlem skjuler. Gæstens vej (entitet_offentlig, fakta-RLS) følger.
DO $$
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO person(id,levende,privat) VALUES (-937801,false,false),(-937802,false,false),(-937803,true,false);
  INSERT INTO family(id,type) VALUES (-937811,'vielse'),(-937812,'vielse'),(-937813,'vielse');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES
    (-937811,-937801,'partner'),(-937811,-937802,'partner'),   -- offentlig
    (-937812,-937801,'partner'),(-937812,-937803,'partner');   -- levende medlem; -937813 har ingen medlemmer
  IF NOT public.family_offentlig(-937811) THEN
    RAISE EXCEPTION 'FEJL: S3 — en familie med kun offentlige medlemmer er ikke offentlig'; END IF;
  IF public.family_offentlig(-937812) THEN
    RAISE EXCEPTION 'FEJL: S3 — en familie med et levende medlem er offentlig'; END IF;
  IF public.family_offentlig(-937813) THEN
    RAISE EXCEPTION 'FEJL: S3 — en familie uden medlemmer er offentlig'; END IF;
  IF public.family_offentlig(-937899) THEN
    RAISE EXCEPTION 'FEJL: S3 — et ikke-eksisterende familie-id er offentligt'; END IF;
  IF public.entitet_offentlig('family',-937813) THEN
    RAISE EXCEPTION 'FEJL: S3 — entitet_offentlig følger ikke family_offentlig for en tom familie'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review37 S3 — en familie uden medlemmer er ikke offentlig';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY r37s3

-- BEGIN-VERIFY r37s8
-- ===== Review 37 S8: gæster og medlemmer læser kun læserens kolonner på story og feed_pin; gæster også på media =====
-- anon har ingen tabelret på de tre tabeller; authenticated har ingen på story/feed_pin og kun SELECT på media
-- (redaktionens medieliste læser original_filnavn/sha256 — kendt rest, #397). Kolonneretterne er PRÆCIS
-- læserlisten (kun SELECT; listen her er bevidst skrevet uafhængigt af db-rls.sql); de interne kolonner er skjult,
-- media.storage_path er en bevidst undtagelse. Udøves også som rolle anon.
DO $$
DECLARE r record; v_fejl text := ''; v_state text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('media','original_filnavn'),('media','sha256'),
      ('story','skabt_af'),('story','godkendt_af'),('story','godkendt_naar'),('story','oprindelse'),
      ('story','llm_model'),('story','llm_promptversion'),('story','llm_naar'),
      ('feed_pin','oprettet_af')) v(t,c) LOOP
    IF has_column_privilege('anon', format('public.%I', r.t), r.c, 'SELECT') THEN
      v_fejl := v_fejl || format(' skjult-men-læsbar:%s.%s', r.t, r.c); END IF;
  END LOOP;
  -- Eksakt mængde: kolonneretterne (alle typer) for anon og authenticated på de tre tabeller = præcis læserlisten.
  -- Fanger både en manglende læserkolonne (fx story.subjekt_type, som forsiden filtrerer på) og en ekstra ret.
  WITH laeser(t,c) AS (VALUES
      ('media','id'),('media','slags'),('media','titel'),('media','kunstner'),('media','datering'),('media','bucket'),
      ('media','storage_path'),('media','mime_type'),('media','byte_size'),('media','bredde'),('media','hoejde'),
      ('media','upload_status'),('media','maa_publiceres'),('media','rettigheder_status'),('media','created_at'),
      ('story','id'),('story','subjekt_type'),('story','subjekt_id'),('story','haendelse_id'),('story','fact_id'),
      ('story','relation_id'),('story','historical_event_id'),('story','titel'),('story','tekst'),('story','date_min'),
      ('story','date_max'),('story','date_qualifier'),('story','date_raw'),('story','status'),('story','publiceret_dato'),
      ('story','privat'),
      ('feed_pin','id'),('feed_pin','kort_noegle'),('feed_pin','handling'),('feed_pin','oprettet_naar')),
  forventet(l) AS (
    SELECT 'anon:'||t||'.'||c||':SELECT' FROM laeser
    UNION ALL SELECT 'authenticated:'||t||'.'||c||':SELECT' FROM laeser WHERE t IN ('story','feed_pin')),
  faktisk(l) AS (
    SELECT x.grantee::regrole::text||':'||c.relname||'.'||at.attname||':'||x.privilege_type
      FROM pg_attribute at JOIN pg_class c ON c.oid=at.attrelid, aclexplode(at.attacl) x
     WHERE c.oid IN ('public.media'::regclass,'public.story'::regclass,'public.feed_pin'::regclass)
       AND at.attnum > 0 AND NOT at.attisdropped AND x.grantee IN ('anon'::regrole,'authenticated'::regrole))
  SELECT v_fejl || coalesce(string_agg(CASE WHEN f.l IS NULL THEN ' læser-kolonne-mangler:'||e.l
                                            ELSE ' uventet-kolonneret:'||f.l END, '' ORDER BY coalesce(e.l,f.l)), '')
    INTO v_fejl
    FROM forventet e FULL JOIN faktisk f ON e.l=f.l WHERE e.l IS NULL OR f.l IS NULL;
  -- Tabelretter: præcis authenticated SELECT på media; intet andet for de to roller.
  SELECT v_fejl || coalesce(string_agg(' uventet-tabelret:'||l, '' ORDER BY l), '')
    INTO v_fejl
    FROM (SELECT x.grantee::regrole::text||':'||c.relname||':'||x.privilege_type AS l
            FROM pg_class c, aclexplode(c.relacl) x
           WHERE c.oid IN ('public.media'::regclass,'public.story'::regclass,'public.feed_pin'::regclass)
             AND x.grantee IN ('anon'::regrole,'authenticated'::regrole)) s
   WHERE l <> 'authenticated:media:SELECT';
  IF NOT has_table_privilege('authenticated','public.media','SELECT') THEN
    v_fejl := v_fejl || ' authenticated-mangler-select:media'; END IF;
  IF EXISTS (SELECT 1 FROM pg_class c, aclexplode(c.relacl) x
              WHERE c.oid IN ('public.media'::regclass,'public.story'::regclass,'public.feed_pin'::regclass) AND x.grantee = 0) THEN
    v_fejl := v_fejl || ' PUBLIC-ret'; END IF;
  IF v_fejl <> '' THEN RAISE EXCEPTION 'FEJL: S8 —%', v_fejl; END IF;

  -- Udøvet som anon: læserens kolonner virker, en skjult kolonne og select * afvises.
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claims','',true);
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM count(*) FROM (SELECT id, storage_path FROM public.media) q;
  PERFORM count(*) FROM (SELECT id, titel, status FROM public.story) q;
  PERFORM count(*) FROM (SELECT kort_noegle, handling, oprettet_naar FROM public.feed_pin) q;
  BEGIN
    PERFORM count(*) FROM (SELECT original_filnavn FROM public.media) q;
    v_state := 'ingen fejl';
  EXCEPTION WHEN insufficient_privilege THEN v_state := '42501'; END;
  IF v_state <> '42501' THEN RAISE EXCEPTION 'FEJL: S8 — anon læste media.original_filnavn (%)', v_state; END IF;
  BEGIN
    PERFORM count(*) FROM (SELECT * FROM public.story) q;
    v_state := 'ingen fejl';
  EXCEPTION WHEN insufficient_privilege THEN v_state := '42501'; END;
  IF v_state <> '42501' THEN RAISE EXCEPTION 'FEJL: S8 — anon læste story.* (%)', v_state; END IF;
  EXECUTE 'RESET ROLE';
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review37 S8 — gæster og medlemmer læser kun læserens kolonner (gæster også på media)';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY r37s8

-- BEGIN-VERIFY r37s5
-- ===== Review 37 S5: ingen storage-bucket er offentlig =====
-- En offentlig bucket serverer filerne uden om storage-politikkerne, så billedgatingen (og S8's undtagelse
-- for media.storage_path) ville være virkningsløs. Springer kun over, hvor storage-kataloget ikke findes
-- (CI har en shim med den private media-bucket; prod har den rigtige).
DO $$
DECLARE v_offentlige text; v_media boolean;
BEGIN
  IF to_regclass('storage.buckets') IS NULL THEN
    RAISE NOTICE 'SPRINGER OVER review37 S5: storage-kataloget er ikke installeret';
    RETURN;
  END IF;
  EXECUTE $q$SELECT string_agg(id, ', ' ORDER BY id) FROM storage.buckets WHERE public$q$ INTO v_offentlige;
  IF v_offentlige IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: S5 — offentlige storage-buckets: %', v_offentlige; END IF;
  EXECUTE $q$SELECT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'media')$q$ INTO v_media;
  IF NOT v_media THEN
    RAISE NOTICE 'SPRINGER OVER review37 S5 (media-delen): ingen media-bucket';
    RETURN;
  END IF;
  RAISE NOTICE 'OK: review37 S5 — ingen storage-bucket er offentlig (media er privat)';
END $$;
-- END-VERIFY r37s5

-- BEGIN-VERIFY r37s8-2
-- ===== Review 37 R37S8-2: anon og authenticated har kun læseret i public; ingen sekvensret; ingen arvet skriveret =====
-- Eksakt mængde: alle ikke-SELECT-retter (tabel- og kolonneniveau) for PUBLIC, anon og authenticated på public-tabeller,
-- -views og -matviews = præcis bookmarks to (authenticated INSERT + DELETE; web/mobil bookmarks.ts). Ingen ret på
-- public-sekvenserne. Standardrettighederne for postgres (ejer af alle public-objekter) giver hverken
-- skriveret på nye tabeller eller ret på nye sekvenser. Listen er bevidst skrevet uafhængigt af db-rls.sql.
-- Udøves også som anon og authenticated (TRUNCATE, UPDATE, nextval afvises; bookmark-INSERT tilladt af rettighederne).
-- Desuden: hver public-tabel har RLS slået til (standard-SELECT på nye tabeller er bevaret, så RLS skal skjule rækkerne).
DO $$
DECLARE v_fejl text; v_state text;
BEGIN
  WITH forventet(l) AS (VALUES ('authenticated:bookmark:DELETE'), ('authenticated:bookmark:INSERT')),
  faktisk(l) AS (
    SELECT CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE x.grantee::regrole::text END||':'||c.relname||':'||x.privilege_type
      FROM pg_class c, aclexplode(c.relacl) x
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p','v','m','f')
       AND x.privilege_type <> 'SELECT' AND x.grantee IN (0, 'anon'::regrole, 'authenticated'::regrole)
    UNION
    SELECT CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE x.grantee::regrole::text END||':'||c.relname||'.'||at.attname||':'||x.privilege_type
      FROM pg_attribute at JOIN pg_class c ON c.oid = at.attrelid, aclexplode(at.attacl) x
     WHERE c.relnamespace = 'public'::regnamespace AND at.attnum > 0 AND NOT at.attisdropped
       AND x.privilege_type <> 'SELECT' AND x.grantee IN (0, 'anon'::regrole, 'authenticated'::regrole)
    UNION
    SELECT 'sekvens:'||CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE x.grantee::regrole::text END||':'||c.relname||':'||x.privilege_type
      FROM pg_class c, aclexplode(c.relacl) x
     WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'S'
       AND x.grantee IN (0, 'anon'::regrole, 'authenticated'::regrole)
    UNION
    SELECT 'standard:'||d.defaclobjtype::text||':'||CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE x.grantee::regrole::text END||':'||x.privilege_type
      FROM pg_default_acl d, aclexplode(d.defaclacl) x
     WHERE d.defaclrole = to_regrole('postgres') AND d.defaclnamespace IN (0, 'public'::regnamespace)
       AND x.grantee IN (0, 'anon'::regrole, 'authenticated'::regrole)
       AND ((d.defaclobjtype = 'r' AND x.privilege_type <> 'SELECT') OR d.defaclobjtype = 'S'))
  SELECT coalesce(string_agg(CASE WHEN f.l IS NULL THEN ' mangler:'||e.l ELSE ' uventet:'||f.l END, ''
                             ORDER BY coalesce(e.l, f.l)), '')
    INTO v_fejl
    FROM forventet e FULL JOIN faktisk f ON e.l = f.l WHERE e.l IS NULL OR f.l IS NULL;
  IF v_fejl <> '' THEN RAISE EXCEPTION 'FEJL: R37S8-2 —%', v_fejl; END IF;
  -- Standard-SELECT på nye public-tabeller er bevidst bevaret, så RLS er det eneste, der skjuler rækkerne: hver
  -- public-tabel skal have RLS slået til (alle 43 har det i prod 2026-11-23). Fanger en ny tabel uden RLS allerede i CI.
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_fejl
    FROM pg_class c WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p') AND NOT c.relrowsecurity;
  IF v_fejl IS NOT NULL THEN RAISE EXCEPTION 'FEJL: R37S8-2 — public-tabel uden RLS: %', v_fejl; END IF;

  -- Udøvet som anon og authenticated (rettighedstjekket sker før RLS, så tomme tabeller og WHERE false er nok).
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  EXECUTE 'SET LOCAL ROLE anon';
  BEGIN
    EXECUTE 'TRUNCATE public.media_variant';
    v_state := 'ingen fejl';
  EXCEPTION WHEN insufficient_privilege THEN v_state := '42501'; END;
  IF v_state <> '42501' THEN RAISE EXCEPTION 'FEJL: R37S8-2 — anon kunne TRUNCATE media_variant (%)', v_state; END IF;
  BEGIN
    EXECUTE 'UPDATE public.person SET id = id WHERE false';
    v_state := 'ingen fejl';
  EXCEPTION WHEN insufficient_privilege THEN v_state := '42501'; END;
  IF v_state <> '42501' THEN RAISE EXCEPTION 'FEJL: R37S8-2 — anon havde UPDATE på person (%)', v_state; END IF;
  BEGIN
    PERFORM nextval('public.person_id_seq');
    v_state := 'ingen fejl';
  EXCEPTION WHEN insufficient_privilege THEN v_state := '42501'; END;
  IF v_state <> '42501' THEN RAISE EXCEPTION 'FEJL: R37S8-2 — anon kunne kalde nextval(person_id_seq) (%)', v_state; END IF;
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    EXECUTE 'DELETE FROM public.fact WHERE false';
    v_state := 'ingen fejl';
  EXCEPTION WHEN insufficient_privilege THEN v_state := '42501'; END;
  IF v_state <> '42501' THEN RAISE EXCEPTION 'FEJL: R37S8-2 — authenticated havde DELETE på fact (%)', v_state; END IF;
  BEGIN
    EXECUTE 'LOCK TABLE public.vocab IN ACCESS SHARE MODE';
    v_state := 'ingen fejl';
  EXCEPTION WHEN insufficient_privilege THEN v_state := '42501'; END;
  -- ACCESS SHARE kræver kun SELECT; strengere låsemodi kræver skrive-/MAINTAIN-ret.
  IF v_state <> 'ingen fejl' THEN RAISE EXCEPTION 'FEJL: R37S8-2 — authenticated mistede læselåsen på vocab (%)', v_state; END IF;
  BEGIN
    EXECUTE 'LOCK TABLE public.vocab IN ACCESS EXCLUSIVE MODE';
    v_state := 'ingen fejl';
  EXCEPTION WHEN insufficient_privilege THEN v_state := '42501'; END;
  IF v_state <> '42501' THEN RAISE EXCEPTION 'FEJL: R37S8-2 — authenticated kunne låse vocab eksklusivt (%)', v_state; END IF;
  -- Review 37 R37S8-2-3: bogmærket skrives, som klienten gør det (PostgREST upsert med ignoreDuplicates =
  -- INSERT … ON CONFLICT DO NOTHING; web/mobil bookmarks.ts), ikke kun has_table_privilege. Ingen rækker (WHERE false):
  -- rettighedstjekket sker før RLS og før data.
  BEGIN
    EXECUTE 'INSERT INTO public.bookmark(person_id) SELECT NULL::bigint WHERE false ON CONFLICT (user_id, person_id) DO NOTHING';
    v_state := 'ingen fejl';
  EXCEPTION WHEN insufficient_privilege THEN v_state := '42501'; END;
  IF v_state <> 'ingen fejl' THEN
    RAISE EXCEPTION 'FEJL: R37S8-2 — authenticated kan ikke skrive bogmærker som klienten (INSERT … ON CONFLICT DO NOTHING) (%)', v_state; END IF;
  EXECUTE 'RESET ROLE';
  -- Review 37 R37S8-2-3: rettighederne ovenfor ses kun direkte. anon og authenticated må derfor ikke arve noget via
  -- rollemedlemskab (prod 2026-11-24: ingen; Supabases authenticator er medlem AF dem, ikke omvendt).
  SELECT string_agg(m.member::regrole::text||'→'||m.roleid::regrole::text, ', ' ORDER BY m.member, m.roleid) INTO v_fejl
    FROM pg_auth_members m WHERE m.member IN ('anon'::regrole, 'authenticated'::regrole);
  IF v_fejl IS NOT NULL THEN RAISE EXCEPTION 'FEJL: R37S8-2 — anon/authenticated arver via rollemedlemskab: %', v_fejl; END IF;
  IF NOT (has_table_privilege('authenticated', 'public.bookmark', 'INSERT')
          AND has_table_privilege('authenticated', 'public.bookmark', 'DELETE')
          AND has_table_privilege('authenticated', 'public.bookmark', 'SELECT')) THEN
    RAISE EXCEPTION 'FEJL: R37S8-2 — authenticated mangler SELECT/INSERT/DELETE på bookmark'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM = 'ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: review37 R37S8-2 — anon og authenticated har kun læseret i public (bookmark: + INSERT/DELETE)';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY r37s8-2

-- BEGIN-VERIFY r37b3-d5a
-- ===== Review 37 D5a: datointervaller i orden på assertion, haendelse, story og relation =====
-- Tabel-CHECK'erne *_dato_orden og relation_periode_orden afviser date_min > date_max, start_min > start_max,
-- end_min > end_max og start_min > end_max; NULL-grænser og start_min > end_min (løse grænser) er tilladt.
-- red_opret_story, red_rediger_story og red_ret_ocr_felt afviser med DATO_INTERVAL_OMVENDT før ændringssættet.
DO $$
DECLARE v_t text; v_ok boolean; v_state text; v_msg text; v_story bigint; v_n_cs bigint; v_fp text;
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  INSERT INTO person(id,levende,privat) VALUES (-937801,false,false);
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-937811,'person',-937801,'embede');
  INSERT INTO narrative(id,subjekt_type,subjekt_id,tekst) VALUES (-937821,'person',-937801,'Syntetisk');
  FOREACH v_t IN ARRAY ARRAY['assertion','haendelse','story','relation_start','relation_slut','relation_start_slut'] LOOP
    v_ok := false;
    BEGIN
      IF v_t = 'assertion' THEN
        INSERT INTO assertion(target_type,target_id,date_min,date_max) VALUES ('fact',-937811,'1851-12-31','1851-01-01');
      ELSIF v_t = 'haendelse' THEN
        INSERT INTO haendelse(subjekt_type,subjekt_id,narrative_id,noegle,klausul,date_min,date_max)
          VALUES ('person',-937801,-937821,'r37b3','x','1851-12-31','1851-01-01');
      ELSIF v_t = 'story' THEN
        INSERT INTO story(subjekt_type,subjekt_id,tekst,date_min,date_max) VALUES ('person',-937801,'x','1851-12-31','1851-01-01');
      ELSIF v_t = 'relation_start' THEN
        INSERT INTO relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,start_min,start_max)
          VALUES ('person',-937801,'estate',-937831,'ejer','1851-12-31','1851-01-01');
      ELSIF v_t = 'relation_slut' THEN
        INSERT INTO relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,end_min,end_max)
          VALUES ('person',-937801,'estate',-937831,'ejer','1851-12-31','1851-01-01');
      ELSE
        INSERT INTO relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,start_min,end_max)
          VALUES ('person',-937801,'estate',-937831,'ejer','1860-01-01','1850-12-31');
      END IF;
    EXCEPTION WHEN check_violation THEN v_ok := true;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'FEJL: D5a — % accepterede et omvendt datointerval', v_t; END IF;
  END LOOP;
  -- Tilladt: lige interval, åbne grænser, og en slutgrænse hvis nedre grænse ligger før starten (løse grænser).
  INSERT INTO assertion(target_type,target_id,date_min,date_max) VALUES ('fact',-937811,'1851-01-01','1851-01-01'),
    ('fact',-937811,NULL,'1851-01-01'),('fact',-937811,'1851-01-01',NULL);
  INSERT INTO relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,start_min,start_max,end_min,end_max)
    VALUES ('person',-937801,'estate',-937831,'ejer','1850-01-01','1855-12-31','1840-01-01','1870-12-31');
  -- Story- og OCR-writerne.
  v_story := red_opret_story('person',-937801,'Syntetisk historie');
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO source(id,slags,titel,import_key) VALUES (-937841,'test','r37b3 ocr','r37b3:ocr');
  INSERT INTO person_external_id(person_id,source_id,record_key) VALUES (-937801,-937841,'R37B3-1');
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-937812,'person',-937801,'fødsel');
  INSERT INTO assertion(id,target_type,target_id,date_raw,date_min,date_max,date_qualifier,uforanderlig)
    VALUES (-937851,'fact',-937812,'1850','1850-01-01','1850-12-31','between',true);
  INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',-937812,-937851,'afklaret');
  INSERT INTO citation(assertion_id,source_id,side,citat_tekst) VALUES (-937851,-937841,'1','født 1850');
  SET LOCAL ROLE authenticated;
  SELECT input_fingerprint->>'foedsel' INTO v_fp FROM red_person_grid() WHERE person_id=-937801;
  RESET ROLE;
  IF v_fp IS NULL THEN RAISE EXCEPTION 'FEJL: D5a — OCR-fixturen gav intet fingerprint'; END IF;
  SELECT count(*) INTO v_n_cs FROM change_set;
  FOREACH v_t IN ARRAY ARRAY['red_opret_story','red_rediger_story','red_ret_ocr_felt'] LOOP
    v_ok := false;
    BEGIN
      IF v_t = 'red_opret_story' THEN
        PERFORM red_opret_story('person',-937801,'x',p_date_min=>'1851-12-31',p_date_max=>'1851-01-01');
      ELSIF v_t = 'red_rediger_story' THEN
        PERFORM red_rediger_story(v_story,'x',p_date_min=>'1851-12-31',p_date_max=>'1851-01-01');
      ELSE
        SET LOCAL ROLE authenticated;
        PERFORM red_ret_ocr_felt(-937801,'r37b3:ocr','R37B3-1','foedsel',v_fp,
          '{"raw":"1851","min":"1851-12-31","max":"1851-01-01","qualifier":"between"}'::jsonb);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      IF v_state = '22023' AND v_msg = 'DATO_INTERVAL_OMVENDT' THEN v_ok := true;
      ELSIF v_state = '23514' THEN v_ok := false;
      ELSE RAISE; END IF;
    END;
    RESET ROLE;
    IF NOT v_ok THEN RAISE EXCEPTION 'FEJL: D5a — % afviste ikke et omvendt interval med DATO_INTERVAL_OMVENDT', v_t; END IF;
    PERFORM set_config('app.change_set_id','',true);
  END LOOP;
  IF (SELECT count(*) FROM change_set) <> v_n_cs THEN
    RAISE EXCEPTION 'FEJL: D5a — en afvist skrivning åbnede et ændringssæt'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review37 D5a — datointervaller i orden på fire tabeller og i story-/OCR-writerne';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY r37b3-d5a

-- BEGIN-VERIFY r37b3-d5b
-- ===== Review 37 D5b: lukkede lister som tabel-CHECKs =====
-- family_member.rolle, family_member.konfidens, relation.konfidens, conclusion.status og date_qualifier på assertion,
-- haendelse og story. NULL er tilladt (ikke for rolle, som er NOT NULL). Hver tilladt værdi accepteres; en ukendt
-- afvises. Redigerings-RPC'erne afviser en ukendt kvalifikator med DATO_KVALIFIKATOR_UGYLDIG før ændringssættet.
DO $$
DECLARE v_t text; v_v text; v_ok boolean; v_state text; v_msg text; v_n_cs bigint; i int := 0;
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  INSERT INTO person(id,levende,privat) SELECT g,false,false FROM generate_series(-937920,-937901) g;
  INSERT INTO family(id,type) SELECT g,'vielse' FROM generate_series(-937936,-937931) g;
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) SELECT g,'person',-937901,'embede' FROM generate_series(-937950,-937941) g;
  INSERT INTO narrative(id,subjekt_type,subjekt_id,tekst) VALUES (-937961,'person',-937901,'Syntetisk');
  -- Ukendte værdier afvises af tabellen (første kontrol er rød på en base uden blok 3).
  FOR v_t, v_v IN SELECT * FROM (VALUES ('family_member.rolle','svigerbarn'),('family_member.konfidens','usikker'),
      ('relation.konfidens','Sikker'),('conclusion.status','aaben'),('assertion.date_qualifier','ca'),
      ('haendelse.date_qualifier','open_start'),('story.date_qualifier','omkring')) x LOOP
    v_ok := false;
    BEGIN
      IF v_t = 'family_member.rolle' THEN
        INSERT INTO family_member(family_id,person_id,rolle) VALUES (-937931,-937901,v_v);
      ELSIF v_t = 'family_member.konfidens' THEN
        INSERT INTO family_member(family_id,person_id,rolle,konfidens) VALUES (-937931,-937901,'partner',v_v);
      ELSIF v_t = 'relation.konfidens' THEN
        INSERT INTO relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,konfidens)
          VALUES ('person',-937901,'estate',-937971,'ejer',v_v);
      ELSIF v_t = 'conclusion.status' THEN
        INSERT INTO conclusion(target_type,target_id,status) VALUES ('fact',-937941,v_v);
      ELSIF v_t = 'assertion.date_qualifier' THEN
        INSERT INTO assertion(target_type,target_id,date_qualifier) VALUES ('fact',-937941,v_v);
      ELSIF v_t = 'haendelse.date_qualifier' THEN
        INSERT INTO haendelse(subjekt_type,subjekt_id,narrative_id,noegle,klausul,date_qualifier)
          VALUES ('person',-937901,-937961,'r37b3','x',v_v);
      ELSE
        INSERT INTO story(subjekt_type,subjekt_id,tekst,date_qualifier) VALUES ('person',-937901,'x',v_v);
      END IF;
    EXCEPTION WHEN check_violation THEN v_ok := true;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'FEJL: D5b — % accepterede den ukendte værdi «%»', v_t, v_v; END IF;
  END LOOP;
  -- Hver tilladt værdi (og NULL) accepteres.
  FOREACH v_v IN ARRAY ARRAY['partner','barn','adopteret_barn','plejebarn','stedbarn'] LOOP
    i := i + 1;
    INSERT INTO family_member(family_id,person_id,rolle) VALUES (-937931,-937901-i,v_v);
  END LOOP;
  FOREACH v_v IN ARRAY ARRAY['sikker','sandsynlig','formodet','omstridt',NULL] LOOP
    i := i + 1;
    INSERT INTO family_member(family_id,person_id,rolle,konfidens) VALUES (-937926-i,-937901-i,'partner',v_v);
    INSERT INTO relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,konfidens)
      VALUES ('person',-937901,'estate',-937971,'ejer',v_v);
  END LOOP;
  i := 0;
  FOREACH v_v IN ARRAY ARRAY['afklaret','omstridt','forældet','tilbagetrukket',NULL] LOOP
    i := i + 1;
    INSERT INTO conclusion(target_type,target_id,status) VALUES ('fact',-937940-i,v_v);
  END LOOP;
  FOREACH v_v IN ARRAY ARRAY['exact','before','after','between','about','floruit','until_event','open_end','ongoing',NULL] LOOP
    INSERT INTO assertion(target_type,target_id,date_qualifier) VALUES ('fact',-937941,v_v);
    INSERT INTO haendelse(subjekt_type,subjekt_id,narrative_id,noegle,klausul,date_qualifier)
      VALUES ('person',-937901,-937961,'r37b3-'||coalesce(v_v,'null'),'x',v_v);
    INSERT INTO story(subjekt_type,subjekt_id,tekst,date_qualifier) VALUES ('person',-937901,'x',v_v);
  END LOOP;
  -- Redigerings-RPC'erne: læsbar fejlkode før CHECK'en og før ændringssættet.
  SELECT count(*) INTO v_n_cs FROM change_set;
  FOREACH v_t IN ARRAY ARRAY['red_upsert_fakta','red_opret_fakta','red_tilfoej_oplysning','red_opret_story'] LOOP
    v_ok := false;
    BEGIN
      IF v_t = 'red_upsert_fakta' THEN PERFORM red_upsert_fakta('person',-937901,'død','1900',NULL,NULL,'ca.','1900');
      ELSIF v_t = 'red_opret_fakta' THEN PERFORM red_opret_fakta('person',-937901,'død','1900',NULL,NULL,'ca.','1900');
      ELSIF v_t = 'red_tilfoej_oplysning' THEN PERFORM red_tilfoej_oplysning(-937941,'1900',NULL,NULL,'ca.','1900');
      ELSE PERFORM red_opret_story('person',-937901,'x',p_date_qualifier=>'ca.');
      END IF;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      IF v_state = '22023' AND v_msg = 'DATO_KVALIFIKATOR_UGYLDIG' THEN v_ok := true;
      ELSIF v_state = '23514' THEN v_ok := false;
      ELSE RAISE; END IF;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'FEJL: D5b — % afviste ikke en ukendt kvalifikator med DATO_KVALIFIKATOR_UGYLDIG', v_t; END IF;
    PERFORM set_config('app.change_set_id','',true);
  END LOOP;
  IF (SELECT count(*) FROM change_set) <> v_n_cs THEN
    RAISE EXCEPTION 'FEJL: D5b — en afvist skrivning åbnede et ændringssæt'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review37 D5b — lukkede lister på syv kolonner, kvalifikatoren afvises i redigerings-RPC''erne';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY r37b3-d5b

-- BEGIN-VERIFY r37p11
-- ===== Review 37 P11: den fortrydelige sletning kun for en offentlig person (én sletteknap) =====
-- red_slet_person afviser en person, der ikke er offentlig, med SLET_KRAEVER_SLET_HELT: <årsag>, og intet ændres
-- (heller intet ændringssæt). En afdød, offentlig person kan stadig slettes — også én i en familie og på et
-- fællesbillede, og ingen familie, intet billede og ingen person bliver mere offentlig af det. red_slet_person_preview
-- giver kan_fortrydes (= person_offentlig) og aarsag (fast prioritet levende → privat → staged → samme_som_skjult;
-- findes_ikke for et ukendt id). Uden redaktørrolle afviser begge med »Kun redaktion«, ens for alle personer (intet
-- orakel). red_slettede_personer (redaktionens liste) viser sletningen med navn, ikke efter fortrydelse, og afviser uden
-- redaktørrolle. Kaldt som ejer med en redaktør-uid; matricen med rigtige klientroller er
-- tests/sql/test-review37-p11-kaldere.sql. At en fuld sletning ikke står på listen, viser testgruppen p11_blindgyde.
DO $$
DECLARE
  r record; v_pv jsonb; v_msg text; v_n_cs bigint; v_foer text; v_efter text; v_cs bigint; v_cs2 bigint;
  v_offentlig_foer jsonb; v_offentlig_efter jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO person(id,levende,privat,staged) VALUES
    (-937901,true ,false,false),  -- levende, gift med den offentlige -937902
    (-937902,false,false,false),  -- offentlig partner (bevares i alle tilfælde)
    (-937903,false,true ,false),  -- afdød, men privat; gift med -937902
    (-937904,false,false,true ),  -- staged dublet fra en ny udgave
    (-937905,false,false,false),  -- afdød og selv offentlig, men samme_som en levende (-937906)
    (-937906,true ,false,false),
    (-937907,NULL ,false,false),  -- levende ukendt (NULL) = levende
    (-937908,true ,true ,true ),  -- alle tre: levende vinder
    (-937909,false,true ,true ),  -- privat + staged: privat vinder
    (-937910,false,false,false),  -- offentlig: i familie med -937902 og på fællesbillede med -937902 → må slettes
    (-937912,false,false,false);  -- offentlig, alene (preview-kontrol)
  INSERT INTO family(id,type) VALUES (-937921,'vielse'),(-937922,'vielse'),(-937923,'vielse');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES
    (-937921,-937901,'partner'),(-937921,-937902,'partner'),
    (-937922,-937903,'partner'),(-937922,-937902,'partner'),
    (-937923,-937910,'partner'),(-937923,-937902,'partner');
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES
    (-937931,'family',-937921,'vielse'),(-937932,'family',-937922,'vielse'),(-937933,'family',-937923,'vielse');
  INSERT INTO media(id,slags,maa_publiceres,upload_status) VALUES (-937941,'portræt',true,'klar'),(-937942,'portræt',true,'klar'),(-937943,'portræt',true,'klar');
  INSERT INTO relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES
    ('person',-937901,'media',-937941,'afbildet'),('person',-937902,'media',-937941,'afbildet'),  -- levende på fællesbillede
    ('person',-937910,'media',-937942,'afbildet'),('person',-937902,'media',-937942,'afbildet'),  -- offentlig på fællesbillede
    ('media',-937943,'family',-937923,'afbildet');                                               -- billede af offentlig familie
  PERFORM red_upsert_fakta('person',-937910,'navn','Verify Slettet P11');
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_samme_som(-937905,-937906);
  PERFORM set_config('app.change_set_id','',true);

  -- Afvisningen: hver ikke-offentlig person med sin årsag; rækkerne og ændringssættene er uændrede bagefter.
  FOR r IN SELECT * FROM (VALUES (-937901::bigint,'levende'),(-937903,'privat'),(-937904,'staged'),
      (-937905,'samme_som_skjult'),(-937907,'levende'),(-937908,'levende'),(-937909,'privat')) x(pid,aarsag) LOOP
    SELECT count(*) INTO v_n_cs FROM change_set;
    SELECT md5(coalesce((SELECT to_jsonb(p)::text FROM person p WHERE p.id=r.pid),'')
      ||coalesce((SELECT string_agg(to_jsonb(fm)::text,',' ORDER BY fm.family_id) FROM family_member fm WHERE fm.person_id=r.pid),'')
      ||coalesce((SELECT string_agg(to_jsonb(x)::text,',' ORDER BY x.id) FROM relation x
                   WHERE (x.subjekt_type='person' AND x.subjekt_id=r.pid) OR (x.objekt_type='person' AND x.objekt_id=r.pid)),''))
      INTO v_foer;
    v_msg:=NULL;
    BEGIN
      PERFORM red_slet_person(r.pid);
    EXCEPTION WHEN OTHERS THEN v_msg:=SQLERRM;
    END;
    IF v_msg IS NULL THEN
      RAISE EXCEPTION 'FEJL: P11 — den simple sletning accepterede person % (forventet afvisning: %)', r.pid, r.aarsag; END IF;
    IF v_msg NOT LIKE 'SLET_KRAEVER_SLET_HELT: '||r.aarsag||' %' THEN
      RAISE EXCEPTION 'FEJL: P11 — person % blev afvist med «%», forventet SLET_KRAEVER_SLET_HELT: %', r.pid, v_msg, r.aarsag; END IF;
    PERFORM set_config('app.change_set_id','',true);
    SELECT md5(coalesce((SELECT to_jsonb(p)::text FROM person p WHERE p.id=r.pid),'')
      ||coalesce((SELECT string_agg(to_jsonb(fm)::text,',' ORDER BY fm.family_id) FROM family_member fm WHERE fm.person_id=r.pid),'')
      ||coalesce((SELECT string_agg(to_jsonb(x)::text,',' ORDER BY x.id) FROM relation x
                   WHERE (x.subjekt_type='person' AND x.subjekt_id=r.pid) OR (x.objekt_type='person' AND x.objekt_id=r.pid)),''))
      INTO v_efter;
    IF v_efter IS DISTINCT FROM v_foer OR (SELECT count(*) FROM change_set) <> v_n_cs THEN
      RAISE EXCEPTION 'FEJL: P11 — den afviste sletning af person % ændrede rækker eller åbnede et ændringssæt', r.pid; END IF;
  END LOOP;

  -- Forhåndsvisningen: kan_fortrydes = person_offentlig, aarsag i fast prioritet, falsk kan_fortrydes har altid en årsag.
  FOR r IN SELECT * FROM (VALUES (-937901::bigint,'levende'),(-937903,'privat'),(-937904,'staged'),
      (-937905,'samme_som_skjult'),(-937906,'levende'),(-937907,'levende'),(-937908,'levende'),(-937909,'privat'),
      (-937902,NULL),(-937910,NULL),(-937912,NULL),(-937999,'findes_ikke')) x(pid,aarsag) LOOP
    v_pv:=red_slet_person_preview(r.pid);
    IF NOT (v_pv ? 'kan_fortrydes') OR NOT (v_pv ? 'aarsag') OR jsonb_typeof(v_pv->'kan_fortrydes') <> 'boolean' THEN
      RAISE EXCEPTION 'FEJL: P11 — forhåndsvisningen mangler kan_fortrydes/aarsag: %', v_pv; END IF;
    IF (v_pv->>'kan_fortrydes')::boolean IS DISTINCT FROM public.person_offentlig(r.pid)
       OR (v_pv->>'aarsag') IS DISTINCT FROM r.aarsag
       OR (NOT (v_pv->>'kan_fortrydes')::boolean AND v_pv->>'aarsag' IS NULL) THEN
      RAISE EXCEPTION 'FEJL: P11 — forhåndsvisningen for person % er kan_fortrydes=%, aarsag=% (forventet aarsag %)',
        r.pid, v_pv->>'kan_fortrydes', v_pv->>'aarsag', coalesce(r.aarsag,'NULL'); END IF;
  END LOOP;

  -- Tilladt: den offentlige -937910 slettes; ingen familie, intet billede og ingen person bliver mere offentlig.
  SELECT jsonb_build_object(
    'fam',(SELECT jsonb_object_agg(f.id,public.family_offentlig(f.id)) FROM family f WHERE f.id BETWEEN -937929 AND -937921),
    'media',(SELECT jsonb_object_agg(m.id,public.media_synlig_anon(m.id)) FROM media m WHERE m.id BETWEEN -937949 AND -937941),
    'person',(SELECT jsonb_object_agg(p.id,public.person_offentlig(p.id)) FROM person p WHERE p.id BETWEEN -937912 AND -937901))
    INTO v_offentlig_foer;
  IF NOT (v_offentlig_foer->'fam'->>'-937923')::boolean OR NOT (v_offentlig_foer->'media'->>'-937942')::boolean
     OR (v_offentlig_foer->'fam'->>'-937921')::boolean OR (v_offentlig_foer->'media'->>'-937941')::boolean THEN
    RAISE EXCEPTION 'FEJL: P11 — fixturen: forventet offentlig -937923/-937942 og skjult -937921/-937941, fik %', v_offentlig_foer; END IF;
  PERFORM red_slet_person(-937910);
  PERFORM set_config('app.change_set_id','',true);
  IF EXISTS (SELECT 1 FROM person WHERE id=-937910) THEN RAISE EXCEPTION 'FEJL: P11 — den offentlige person blev ikke slettet'; END IF;
  IF NOT EXISTS (SELECT 1 FROM change_set WHERE operation='red_slet_person' AND subjekt_type='person' AND subjekt_id=-937910) THEN
    RAISE EXCEPTION 'FEJL: P11 — sletningen af den offentlige person har intet ændringssæt (kan ikke fortrydes)'; END IF;
  SELECT jsonb_build_object(
    'fam',(SELECT jsonb_object_agg(f.id,public.family_offentlig(f.id)) FROM family f WHERE f.id BETWEEN -937929 AND -937921),
    'media',(SELECT jsonb_object_agg(m.id,public.media_synlig_anon(m.id)) FROM media m WHERE m.id BETWEEN -937949 AND -937941),
    'person',(SELECT jsonb_object_agg(p.id,public.person_offentlig(p.id)) FROM person p WHERE p.id BETWEEN -937912 AND -937901))
    INTO v_offentlig_efter;
  FOR r IN SELECT k.typ, e.key, e.value AS efter FROM (VALUES ('fam'),('media'),('person')) k(typ)
             CROSS JOIN LATERAL jsonb_each(v_offentlig_efter->k.typ) e LOOP
    IF (r.efter #>> '{}')::boolean AND NOT coalesce((v_offentlig_foer->r.typ->>r.key)::boolean,false) THEN
      RAISE EXCEPTION 'FEJL: P11 — sletningen af en offentlig person gjorde % % offentlig', r.typ, r.key; END IF;
  END LOOP;

  -- Listen over slettede personer: sletningen står med navn og sæt; efter fortrydelse er den væk; en ny sletning står igen.
  SELECT max(id) INTO v_cs FROM change_set WHERE operation='red_slet_person' AND subjekt_type='person' AND subjekt_id=-937910;
  IF NOT EXISTS (SELECT 1 FROM red_slettede_personer(500) l
                  WHERE l.change_set_id=v_cs AND l.person_id=-937910 AND l.navn='Verify Slettet P11'
                    AND l.slettet_naar IS NOT NULL) THEN
    RAISE EXCEPTION 'FEJL: P11 — listen over slettede personer mangler sletningen af -937910 med navn (sæt %)', v_cs; END IF;
  IF EXISTS (SELECT 1 FROM red_slettede_personer(500) l WHERE l.person_id IN (-937901,-937902,-937903,-937904,-937905)) THEN
    RAISE EXCEPTION 'FEJL: P11 — listen over slettede personer viser en person, der ikke er slettet'; END IF;
  PERFORM red_fortryd_change_set(v_cs,false);
  PERFORM set_config('app.change_set_id','',true);
  IF NOT EXISTS (SELECT 1 FROM person WHERE id=-937910)
     OR EXISTS (SELECT 1 FROM red_slettede_personer(500) l WHERE l.change_set_id=v_cs OR l.person_id=-937910) THEN
    RAISE EXCEPTION 'FEJL: P11 — en fortrudt sletning står stadig på listen over slettede personer'; END IF;
  PERFORM red_slet_person(-937910);
  PERFORM set_config('app.change_set_id','',true);
  SELECT max(id) INTO v_cs2 FROM change_set WHERE operation='red_slet_person' AND subjekt_type='person' AND subjekt_id=-937910;
  IF v_cs2 = v_cs OR (SELECT count(*) FROM red_slettede_personer(500) l WHERE l.person_id=-937910) <> 1
     OR NOT EXISTS (SELECT 1 FROM red_slettede_personer(500) l WHERE l.change_set_id=v_cs2) THEN
    RAISE EXCEPTION 'FEJL: P11 — en ny sletning efter fortrydelse står ikke præcis én gang på listen'; END IF;
  IF (SELECT count(*) FROM red_slettede_personer(1)) <> 1 THEN
    RAISE EXCEPTION 'FEJL: P11 — p_limit begrænser ikke listen over slettede personer'; END IF;

  -- Intet orakel: uden redaktørrolle samme afvisning for en offentlig og en ikke-offentlig person.
  PERFORM set_config('request.jwt.claim.sub','',true);
  FOR r IN SELECT * FROM (VALUES (-937902::bigint),(-937901),(-937999)) x(pid) LOOP
    v_msg:=NULL;
    BEGIN PERFORM red_slet_person(r.pid); EXCEPTION WHEN OTHERS THEN v_msg:=SQLERRM; END;
    IF v_msg IS DISTINCT FROM 'Kun redaktion' THEN
      RAISE EXCEPTION 'FEJL: P11 — red_slet_person(%) uden redaktørrolle gav «%», forventet «Kun redaktion»', r.pid, v_msg; END IF;
    v_msg:=NULL;
    BEGIN PERFORM red_slet_person_preview(r.pid); EXCEPTION WHEN OTHERS THEN v_msg:=SQLERRM; END;
    IF v_msg IS DISTINCT FROM 'Kun redaktion' THEN
      RAISE EXCEPTION 'FEJL: P11 — red_slet_person_preview(%) uden redaktørrolle gav «%», forventet «Kun redaktion»', r.pid, v_msg; END IF;
  END LOOP;
  v_msg:=NULL;
  BEGIN PERFORM * FROM red_slettede_personer(); EXCEPTION WHEN OTHERS THEN v_msg:=SQLERRM; END;
  IF v_msg IS DISTINCT FROM 'Kun redaktion' THEN
    RAISE EXCEPTION 'FEJL: P11 — red_slettede_personer uden redaktørrolle gav «%», forventet «Kun redaktion»', v_msg; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review37 P11 — den fortrydelige sletning kun for en offentlig person; forhåndsvisningen viser vejen';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY r37p11

-- BEGIN-VERIFY r37d4
-- ===== Review 37 D4: »Gør til konklusion« gør konklusionen gyldig igen =====
-- red_set_konklusion er redaktørens eksplicitte valg og sætter derfor status 'afklaret' uanset den gamle status (samme
-- regel som red_upsert_fakta og red_vaelg_foraeldre; projektejeren 2026-11-22). Før rettelsen skiftede kaldet kun den
-- valgte påstand: en tilbagetrukket konklusion forblev tilbagetrukket og skjult, og kaldet meldte succes. Testen kræver
-- den synlige effekt (visningscachen), ikke kun kolonnen: tilbagetrukket navn → valg af en anden oplysning → navnet vises;
-- tilbagetrukket igen → valg af den SAMME oplysning → vises igen. En omstridt relationskonklusion bliver også afklaret.
-- ACL: kun authenticated (og ejeren) må kalde. Kaldt som ejer med en redaktør-uid.
DO $$
DECLARE
  v_fact bigint; v_a1 bigint; v_a2 bigint; v_rel bigint; v_ra bigint; v_st text; v_valgt bigint; v_navn text;
  v_acl text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO person(id,levende,privat,staged) VALUES (-937401,false,false,false),(-937402,false,false,false);

  v_fact := (red_upsert_fakta('person',-937401,'navn','Verify Første D4')->>'fact_id')::bigint;
  PERFORM set_config('app.change_set_id','',true);
  v_a1 := (SELECT valgt_assertion_id FROM conclusion WHERE target_type='fact' AND target_id=v_fact);
  v_a2 := (red_tilfoej_oplysning(v_fact,'Verify Anden D4')->>'assertion_id')::bigint;
  PERFORM set_config('app.change_set_id','',true);
  IF v_a1 IS NULL OR v_a2 IS NULL OR v_a1 = v_a2 THEN
    RAISE EXCEPTION 'FEJL: D4 — fixturen gav ikke to påstande på ét faktum (a1=%, a2=%)', v_a1, v_a2; END IF;
  IF (SELECT visning_navn FROM person WHERE id=-937401) IS DISTINCT FROM 'Verify Første D4' THEN
    RAISE EXCEPTION 'FEJL: D4 — fixturen viste ikke navnet før tilbagetrækningen'; END IF;

  -- 1) Tilbagetrukket → valg af en ANDEN oplysning.
  PERFORM red_tilbagetraek_fakta(v_fact);
  PERFORM set_config('app.change_set_id','',true);
  IF (SELECT visning_navn FROM person WHERE id=-937401) IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: D4 — fixturen: det tilbagetrukne navn vises stadig'; END IF;
  PERFORM red_set_konklusion(v_a2);
  PERFORM set_config('app.change_set_id','',true);
  SELECT status, valgt_assertion_id INTO v_st, v_valgt FROM conclusion WHERE target_type='fact' AND target_id=v_fact;
  v_navn := (SELECT visning_navn FROM person WHERE id=-937401);
  IF v_st IS DISTINCT FROM 'afklaret' OR v_valgt IS DISTINCT FROM v_a2 OR v_navn IS DISTINCT FROM 'Verify Anden D4' THEN
    RAISE EXCEPTION 'FEJL: D4 — valg på en tilbagetrukket konklusion: status %, valgt % (forventet %), vist navn «%»',
      v_st, v_valgt, v_a2, v_navn; END IF;

  -- 2) Tilbagetrukket → valg af den SAMME oplysning.
  PERFORM red_tilbagetraek_fakta(v_fact);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_set_konklusion(v_a2);
  PERFORM set_config('app.change_set_id','',true);
  SELECT status INTO v_st FROM conclusion WHERE target_type='fact' AND target_id=v_fact;
  v_navn := (SELECT visning_navn FROM person WHERE id=-937401);
  IF v_st IS DISTINCT FROM 'afklaret' OR v_navn IS DISTINCT FROM 'Verify Anden D4' THEN
    RAISE EXCEPTION 'FEJL: D4 — genvalg af den tilbagetrukne oplysning: status %, vist navn «%»', v_st, v_navn; END IF;

  -- 3) En omstridt relationskonklusion: redaktørens valg afklarer den.
  INSERT INTO relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',-937401,'person',-937402,'verify_d4') RETURNING id INTO v_rel;
  INSERT INTO assertion(target_type,target_id,vaerdi_tekst,uforanderlig) VALUES ('relation',v_rel,'verify_d4',true)
    RETURNING id INTO v_ra;
  INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('relation',v_rel,v_ra,'omstridt');
  PERFORM red_set_konklusion(v_ra);
  PERFORM set_config('app.change_set_id','',true);
  SELECT status INTO v_st FROM conclusion WHERE target_type='relation' AND target_id=v_rel;
  IF v_st IS DISTINCT FROM 'afklaret' THEN
    RAISE EXCEPTION 'FEJL: D4 — valg på en omstridt relationskonklusion gav status %', v_st; END IF;

  -- ACL: uændret (ingen anon, ingen PUBLIC).
  SELECT coalesce(p.proacl::text,'NULL') INTO v_acl FROM pg_proc p WHERE p.oid='public.red_set_konklusion(bigint)'::regprocedure;
  IF has_function_privilege('anon','public.red_set_konklusion(bigint)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_set_konklusion(bigint)','EXECUTE') THEN
    RAISE EXCEPTION 'FEJL: D4 — red_set_konklusion har forkert ACL: %', v_acl; END IF;

  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review37 D4 — »Gør til konklusion« gør konklusionen gyldig igen';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY r37d4

-- BEGIN-VERIFY r37d10
-- ===== Review 37 D10: en ny forældre-påstand på et tilbagetrukket slot er ikke en konflikt =====
-- Et tilbagetrukket forældrefamilie-slot (fx efter red_slet_familie_link af barnet) har ingen gældende konklusion. En ny
-- påstand dér behandles som på et slot uden konklusion: matcher den barnets projicerede række, bliver den den afklarede
-- konklusion; ellers står den som kandidat, og slottet forbliver tilbagetrukket. Før rettelsen gav den »konflikt«,
-- satte slottet til 'omstridt' og barnets projektionsrække til konfidens 'omstridt'. Modprøve: et slot med en gældende
-- (afklaret) konklusion giver stadig konflikt.
DO $$
DECLARE
  v_res jsonb; v_st text; v_valgt bigint; v_fact bigint; v_konf text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO person(id,levende,privat,staged) VALUES
    (-937501,false,false,false),(-937502,false,false,false),(-937503,false,false,false),  -- børn A, B, C
    (-937506,false,false,false),(-937507,false,false,false);                              -- forældre i F1, F2
  INSERT INTO family(id,type) VALUES (-937511,'vielse'),(-937512,'vielse');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES
    (-937511,-937506,'partner'),(-937512,-937507,'partner'),
    (-937511,-937501,'barn'),(-937511,-937502,'barn'),(-937511,-937503,'barn');
  -- Alle tre børn: påstand F1 (matcher projektionen) → afklaret slot.
  PERFORM red_tilfoej_foraeldre_paastand(-937501,-937511); PERFORM set_config('app.change_set_id','',true);
  PERFORM red_tilfoej_foraeldre_paastand(-937502,-937511); PERFORM set_config('app.change_set_id','',true);
  PERFORM red_tilfoej_foraeldre_paastand(-937503,-937511); PERFORM set_config('app.change_set_id','',true);
  -- A og B fjernes fra F1 → deres slot er tilbagetrukket.
  PERFORM red_slet_familie_link(-937511,-937501,'barn'); PERFORM set_config('app.change_set_id','',true);
  PERFORM red_slet_familie_link(-937511,-937502,'barn'); PERFORM set_config('app.change_set_id','',true);
  IF (SELECT count(*) FROM conclusion c JOIN fact f ON c.target_type='fact' AND f.id=c.target_id
       WHERE f.faktatype='forældrefamilie' AND f.subjekt_id IN (-937501,-937502) AND c.status='tilbagetrukket') <> 2 THEN
    RAISE EXCEPTION 'FEJL: D10 — fixturen gav ikke to tilbagetrukne slots'; END IF;

  -- A: ny påstand F2, A har ingen projektionsrække → kandidat; slottet forbliver tilbagetrukket.
  v_res := red_tilfoej_foraeldre_paastand(-937501,-937512); PERFORM set_config('app.change_set_id','',true);
  v_fact := (v_res->>'fact_id')::bigint;
  SELECT status INTO v_st FROM conclusion WHERE target_type='fact' AND target_id=v_fact;
  IF (v_res->>'konflikt')::boolean OR v_st IS DISTINCT FROM 'tilbagetrukket' THEN
    RAISE EXCEPTION 'FEJL: D10 — påstand på tilbagetrukket slot uden projektion: konflikt %, status %',
      v_res->>'konflikt', v_st; END IF;

  -- B: projiceret i F2 (direkte række, konfidens sikker), ny påstand F2 → afklaret konklusion på den nye påstand.
  INSERT INTO family_member(family_id,person_id,rolle,konfidens) VALUES (-937512,-937502,'barn','sikker');
  v_res := red_tilfoej_foraeldre_paastand(-937502,-937512); PERFORM set_config('app.change_set_id','',true);
  v_fact := (v_res->>'fact_id')::bigint;
  SELECT status, valgt_assertion_id INTO v_st, v_valgt FROM conclusion WHERE target_type='fact' AND target_id=v_fact;
  v_konf := (SELECT konfidens FROM family_member WHERE person_id=-937502 AND rolle='barn');
  IF (v_res->>'konflikt')::boolean OR v_st IS DISTINCT FROM 'afklaret'
     OR v_valgt IS DISTINCT FROM (v_res->>'assertion_id')::bigint OR v_konf IS DISTINCT FROM 'sikker' THEN
    RAISE EXCEPTION 'FEJL: D10 — påstand på tilbagetrukket slot, der matcher projektionen: konflikt %, status %, valgt % (forventet %), konfidens %',
      v_res->>'konflikt', v_st, v_valgt, v_res->>'assertion_id', v_konf; END IF;

  -- Modprøve C: gældende (afklaret) slot F1, ny påstand F2 → konflikt, omstridt.
  v_res := red_tilfoej_foraeldre_paastand(-937503,-937512); PERFORM set_config('app.change_set_id','',true);
  SELECT status INTO v_st FROM conclusion WHERE target_type='fact' AND target_id=(v_res->>'fact_id')::bigint;
  IF NOT (v_res->>'konflikt')::boolean OR v_st IS DISTINCT FROM 'omstridt' THEN
    RAISE EXCEPTION 'FEJL: D10 — modprøven: rivaliserende påstand på afklaret slot gav konflikt %, status %',
      v_res->>'konflikt', v_st; END IF;

  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review37 D10 — en ny forældre-påstand på et tilbagetrukket slot er ikke en konflikt';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY r37d10

-- BEGIN-VERIFY r37d11
-- ===== Review 37 D11: ukendt id giver en ærlig fejl, ikke falsk succes og et tomt ændringssæt =====
-- red_set_koen og red_set_privat afviser en ukendt person med »Person <id> findes ikke«, og red_slet_oplysning en ukendt
-- påstand med »Oplysning <id> findes ikke«, efter rollegaten og før et ændringssæt åbnes. Før rettelsen åbnede de et
-- ændringssæt, ændrede intet og meldte succes. Kontrol: på kendte id'er virker de stadig. Uden redaktørrolle afvises
-- et ukendt id stadig med »Kun redaktion« (intet orakel om, hvilke id'er findes).
DO $$
DECLARE
  r record; v_msg text; v_n_cs bigint; v_aid bigint; v_fact bigint;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO person(id,levende,privat,staged,koen) VALUES (-937601,false,false,false,NULL);

  FOR r IN SELECT * FROM (VALUES
      ('koen',   'Person -937699 findes ikke'),
      ('privat', 'Person -937699 findes ikke'),
      ('slet',   'Oplysning -937699 findes ikke')) x(fn,forventet) LOOP
    SELECT count(*) INTO v_n_cs FROM change_set;
    v_msg := NULL;
    BEGIN
      IF r.fn='koen' THEN PERFORM red_set_koen(-937699,'mand');
      ELSIF r.fn='privat' THEN PERFORM red_set_privat(-937699,true);
      ELSE PERFORM red_slet_oplysning(-937699); END IF;
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    PERFORM set_config('app.change_set_id','',true);
    IF v_msg IS DISTINCT FROM r.forventet THEN
      RAISE EXCEPTION 'FEJL: D11 — % med ukendt id gav «%», forventet «%»', r.fn, coalesce(v_msg,'(succes)'), r.forventet; END IF;
    IF (SELECT count(*) FROM change_set) <> v_n_cs THEN
      RAISE EXCEPTION 'FEJL: D11 — % med ukendt id efterlod et ændringssæt', r.fn; END IF;
  END LOOP;

  -- Kendte id'er virker stadig.
  PERFORM red_set_koen(-937601,'kvinde'); PERFORM set_config('app.change_set_id','',true);
  PERFORM red_set_privat(-937601,true);   PERFORM set_config('app.change_set_id','',true);
  IF (SELECT koen FROM person WHERE id=-937601) IS DISTINCT FROM 'kvinde'
     OR (SELECT privat FROM person WHERE id=-937601) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FEJL: D11 — red_set_koen/red_set_privat virker ikke længere på en kendt person'; END IF;
  v_fact := (red_upsert_fakta('person',-937601,'titel','Verify D11')->>'fact_id')::bigint;
  PERFORM set_config('app.change_set_id','',true);
  v_aid := (red_tilfoej_oplysning(v_fact,'Verify D11 anden')->>'assertion_id')::bigint;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_slet_oplysning(v_aid); PERFORM set_config('app.change_set_id','',true);
  IF EXISTS (SELECT 1 FROM assertion WHERE id=v_aid) THEN
    RAISE EXCEPTION 'FEJL: D11 — red_slet_oplysning sletter ikke længere en kendt oplysning'; END IF;

  -- Uden redaktørrolle: »Kun redaktion«, også for et ukendt id.
  UPDATE profiles SET rolle='medlem' WHERE id='00000000-0000-0000-0000-000000000001';
  FOR r IN SELECT * FROM (VALUES ('koen'),('privat'),('slet')) x(fn) LOOP
    v_msg := NULL;
    BEGIN
      IF r.fn='koen' THEN PERFORM red_set_koen(-937699,'mand');
      ELSIF r.fn='privat' THEN PERFORM red_set_privat(-937699,true);
      ELSE PERFORM red_slet_oplysning(-937699); END IF;
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    IF v_msg IS DISTINCT FROM 'Kun redaktion' THEN
      RAISE EXCEPTION 'FEJL: D11 — % uden redaktørrolle gav «%», forventet «Kun redaktion»', r.fn, coalesce(v_msg,'(succes)'); END IF;
  END LOOP;

  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review37 D11 — ukendt id giver en ærlig fejl uden ændringssæt';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY r37d11

-- BEGIN-VERIFY r37p11-2
-- ===== Review 37 R37P11-2: redaktøren kan rette levende (red_set_levende), fortrydeligt =====
-- Levende → afdød gør en ellers offentlig person synlig for gæster (person_offentlig), afdød → levende skjuler den igen.
-- Hver ændring er sit eget ændringssæt (operation red_set_levende), og en fortrydelse genskaber værdien. Ukendt id og
-- NULL afvises uden ændringssæt; uden redaktørrolle »Kun redaktion«, også for et ukendt id.
DO $$
DECLARE
  v_msg text; v_state text; v_n_cs bigint; v_cs bigint;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO person(id,levende,privat,staged) VALUES (-937621,true,false,false);
  IF public.person_offentlig(-937621) THEN
    RAISE EXCEPTION 'FEJL: R37P11-2 — en levende person er offentlig før ændringen'; END IF;

  -- Levende → afdød: synlig for gæster, eget ændringssæt.
  PERFORM red_set_levende(-937621,false);
  v_cs := current_setting('app.change_set_id')::bigint; PERFORM set_config('app.change_set_id','',true);
  IF (SELECT levende FROM person WHERE id=-937621) IS DISTINCT FROM false OR NOT public.person_offentlig(-937621) THEN
    RAISE EXCEPTION 'FEJL: R37P11-2 — afdød-retningen gjorde ikke personen offentlig'; END IF;
  IF (SELECT operation FROM change_set WHERE id=v_cs) IS DISTINCT FROM 'red_set_levende' THEN
    RAISE EXCEPTION 'FEJL: R37P11-2 — ændringen fik ikke sit eget ændringssæt'; END IF;

  -- Fortryd genskaber levende=true og skjuler personen igen.
  PERFORM red_fortryd_change_set(v_cs); PERFORM set_config('app.change_set_id','',true);
  IF (SELECT levende FROM person WHERE id=-937621) IS DISTINCT FROM true OR public.person_offentlig(-937621) THEN
    RAISE EXCEPTION 'FEJL: R37P11-2 — fortrydelsen genskabte ikke levende=true'; END IF;

  -- Afdød → levende via RPC'en skjuler også.
  UPDATE person SET levende=false WHERE id=-937621;
  PERFORM red_set_levende(-937621,true); PERFORM set_config('app.change_set_id','',true);
  IF public.person_offentlig(-937621) THEN
    RAISE EXCEPTION 'FEJL: R37P11-2 — levende-retningen skjulte ikke personen'; END IF;

  -- Ukendt id og NULL: fejl uden ændringssæt.
  SELECT count(*) INTO v_n_cs FROM change_set;
  v_msg := NULL;
  BEGIN PERFORM red_set_levende(-937699,false); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  PERFORM set_config('app.change_set_id','',true);
  IF v_msg IS DISTINCT FROM 'Person -937699 findes ikke' THEN
    RAISE EXCEPTION 'FEJL: R37P11-2 — ukendt id gav «%»', coalesce(v_msg,'(succes)'); END IF;
  v_msg := NULL; v_state := NULL;
  BEGIN PERFORM red_set_levende(-937621,NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; v_state := SQLSTATE; END;
  PERFORM set_config('app.change_set_id','',true);
  IF v_msg IS DISTINCT FROM 'LEVENDE_UGYLDIG' OR v_state IS DISTINCT FROM '22023' THEN
    RAISE EXCEPTION 'FEJL: R37P11-2 — NULL gav «%» (%)', coalesce(v_msg,'(succes)'), v_state; END IF;
  -- Uændret værdi (fx fra en forældet visning): afvises, så der ikke opstår et tomt, virkningsløst ændringssæt.
  v_msg := NULL;
  BEGIN PERFORM red_set_levende(-937621,true); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  PERFORM set_config('app.change_set_id','',true);
  IF v_msg IS DISTINCT FROM 'LEVENDE_UAENDRET' THEN
    RAISE EXCEPTION 'FEJL: R37P11-2 — uændret værdi gav «%»', coalesce(v_msg,'(succes)'); END IF;
  IF (SELECT count(*) FROM change_set) <> v_n_cs THEN
    RAISE EXCEPTION 'FEJL: R37P11-2 — en afvist ændring efterlod et ændringssæt'; END IF;

  -- Uden redaktørrolle.
  UPDATE profiles SET rolle='medlem' WHERE id='00000000-0000-0000-0000-000000000001';
  v_msg := NULL;
  BEGIN PERFORM red_set_levende(-937699,false); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg IS DISTINCT FROM 'Kun redaktion' THEN
    RAISE EXCEPTION 'FEJL: R37P11-2 — uden redaktørrolle gav «%»', coalesce(v_msg,'(succes)'); END IF;

  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review37 R37P11-2 — redaktøren kan rette levende, fortrydeligt';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY r37p11-2

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
    '_row_pk(text, jsonb)','_version_pk_where(text, jsonb)','_version_current_row(text, jsonb)',
    -- Review 37 R37S8-2-3: siden R37S8-2 skriver ingen klient i narrative/note, så også denne er revoked
    -- (DO-blokken $review37_c1_execute$ i db-rls.sql).
    '_regen_mentions_for(text, bigint)']
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
  RAISE NOTICE 'OK: interne _-helpers ikke anon-kaldbare (REVOKE + guard)';
END $$;

-- ===== Dato-hærdning A1: additive felter (plan Spor A, 2026-07-17) =====
DO $$
DECLARE v_mangler text;
BEGIN
  DELETE FROM assertion WHERE id BETWEEN -987654326 AND -987654321;  -- ryd evt. residual fra fejlet kørsel
  -- Task 8a: rigtigt syntetisk mål; mål-vagten må ikke skygge for CHECK-testen.
  INSERT INTO public.person(id,levende,privat) VALUES (-987654320,false,false);
  INSERT INTO public.fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-987654320,'person',-987654320,'test');
  -- (1) date_certainty-kolonne findes
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='assertion' AND column_name='date_certainty') THEN
    RAISE EXCEPTION 'A1: assertion.date_certainty-kolonne mangler'; END IF;
  -- (2) CHECK afviser ugyldig værdi
  BEGIN
    INSERT INTO assertion (id,target_type,target_id,date_certainty) VALUES (-987654321,'fact',-987654320,'sikker-forkert');
    RAISE EXCEPTION 'A1: date_certainty-CHECK fyrede ikke på ugyldig værdi';
  EXCEPTION WHEN check_violation THEN NULL;  -- forventet
  END;
  -- (3) gyldige værdier + NULL tillades
  INSERT INTO assertion (id,target_type,target_id,date_certainty) VALUES
    (-987654322,'fact',-987654320,'certain'),(-987654323,'fact',-987654320,'uncertain'),
    (-987654324,'fact',-987654320,'ambiguous'),(-987654325,'fact',-987654320,NULL);
  -- (4) calendar-DEFAULT anvendes når kolonnen udelades
  INSERT INTO assertion (id,target_type,target_id) VALUES (-987654326,'fact',-987654320);
  IF (SELECT calendar FROM assertion WHERE id=-987654326) IS DISTINCT FROM 'gregoriansk' THEN
    RAISE EXCEPTION 'A1: calendar-DEFAULT er ikke gregoriansk'; END IF;
  -- (5) faktavokabular seedet (kerne-dato-/event-typer)
  SELECT string_agg(w.code,' ') INTO v_mangler FROM (VALUES
    ('fødsel'),('dåb'),('død'),('begravelse'),('floruit'),('naturalisering'),('introduktion_ridderhus'))
    AS w(code) WHERE NOT EXISTS (SELECT 1 FROM vocab WHERE scheme='faktatype' AND vocab.code=w.code);
  IF v_mangler IS NOT NULL THEN RAISE EXCEPTION 'A1: faktatype-vokabular mangler: %', v_mangler; END IF;
  DELETE FROM assertion WHERE id BETWEEN -987654326 AND -987654321;  -- oprydning
  DELETE FROM public.fact WHERE id=-987654320;
  DELETE FROM public.person WHERE id=-987654320;
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
  -- Task 8a: lokale forældre før polymorfe testbørn; rulles tilbage med scenariet.
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO public.person(id,levende,privat) VALUES (-999951,false,false) ON CONFLICT (id) DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO auth.users(id,email) VALUES ('00000000-0000-0000-0000-000000000001','db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);

  INSERT INTO media(slags,titel,kunstner,datering,upload_status,maa_publiceres)
    VALUES ('portræt','Gammel titel','Gammel kunstner','1699','klar',false)
    RETURNING id INTO v_id;

  SELECT count(*) INTO v_cs_foer FROM change_set;
  PERFORM red_opdater_media(v_id, 'Ny titel', NULL, '', 'ca. 1700');
  IF NOT EXISTS (SELECT 1 FROM media WHERE id=v_id AND titel='Ny titel' AND slags='portræt'
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
  -- Task 8a: lokale forældre før polymorfe testbørn; rulles tilbage med scenariet.
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO public.person(id,levende,privat) VALUES (-999941,false,false) ON CONFLICT (id) DO NOTHING;
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
  -- Task 8a: lokale forældre før polymorfe testbørn; rulles tilbage med scenariet.
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO public.person(id,levende,privat) VALUES (-999942,false,false) ON CONFLICT (id) DO NOTHING;
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
  -- Task 8a: lokale forældre før polymorfe testbørn; rulles tilbage med scenariet.
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO public.person(id,levende,privat) VALUES (-999943,false,false) ON CONFLICT (id) DO NOTHING;
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

-- Fødenavn (#401, spec 2026-11-20-foedenavn-design.md): præsenslistens født-klausul læser faktatypen direkte.
-- Forvent: NOTICE "OK: fødenavn-faktatype".
DO $verify_foedenavn$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM vocab WHERE scheme='faktatype' AND code='fødenavn') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: fødenavn-faktatype mangler';
  END IF;
  RAISE NOTICE 'OK: fødenavn-faktatype';
END $verify_foedenavn$;

-- Adelsnavn (plan docs/superpowers/plans/2026-11-26-linjernes-adelsnavn.md): linjens navn efter titlen (»af Reventlow«)
-- som kildebundet faktum på lineage; læserfladen sammensætter bogens formelle navneform af det.
-- Forvent: NOTICE "OK: adelsnavn-faktatype".
DO $verify_adelsnavn$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM vocab WHERE scheme='faktatype' AND code='adelsnavn') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: adelsnavn-faktatype mangler';
  END IF;
  RAISE NOTICE 'OK: adelsnavn-faktatype';
END $verify_adelsnavn$;

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

-- Trin 5b del 2a (#151, spec 2026-10-11 §4.1): regeltypen structural_family er adskilt fra
-- assertion-vejen; én CHECK pr. regeltype, ingen gammel overload, relationsregler aldrig promoverbare.
DO $relation_binding_rule_verify$
BEGIN
  IF (SELECT attnotnull FROM pg_attribute WHERE attrelid='private.interpretation_promotion_rule'::regclass AND attname='expected_fact_type')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='private.interpretation_promotion_rule'::regclass
                     AND conname='interpretation_promotion_rule_mode_check')
     -- NULL i en CHECK godtages; text_assertion-grenen skal eksplicit kræve faktatypen
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='private.interpretation_promotion_rule'::regclass
                     AND conname='interpretation_promotion_rule_mode_check'
                     AND pg_get_constraintdef(oid) LIKE '%expected_fact_type IS NOT NULL%')
     OR EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='private.interpretation_promotion_rule'::regclass
                 AND conname IN ('interpretation_promotion_rule_interpretation_kind_check','interpretation_promotion_rule_target_type_check',
                                 'interpretation_promotion_rule_expected_fact_type_check','interpretation_promotion_rule_value_kind_check'))
     OR to_regprocedure('private.add_interpretation_promotion_rule_version(text,text,text,text,text,text,boolean,boolean,boolean,text)') IS NOT NULL
     OR (SELECT count(*) FROM private.interpretation_promotion_rule_current
          WHERE rule_key IN ('relation-marriage-v1','relation-parent-v1') AND rule_mode='structural_family' AND status='active')<>2
     OR EXISTS (SELECT 1 FROM private.interpretation_predicate_promotable WHERE predicate LIKE 'relation.%') THEN
    RAISE EXCEPTION 'RELATION_BINDING_RULE_CONTRACT_INVALID';
  END IF;
  RAISE NOTICE 'OK: 5b 2a — regeltypen structural_family';
END $relation_binding_rule_verify$;

-- Trin 5b del 2a (#151, spec §4.2, §4.5, §4.6): tilstandsfunktionen er privat, klassifikationerne
-- append-only bag RLS, ét familiemål pr. fortolkning, og del 1's kontroltabeller står i RLS-masterlisten.
DO $relation_binding_state_verify$
DECLARE v_t text;
BEGIN
  IF to_regclass('private.relation_classification_event') IS NULL
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private.relation_classification_event'::regclass)
     OR has_table_privilege('anon','private.relation_classification_event','SELECT')
     OR has_table_privilege('authenticated','private.relation_classification_event','SELECT')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.relation_classification_event'::regclass
                     AND tgname='trg_relation_classification_event_append_only')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.relation_classification_event'::regclass
                     AND tgname='trg_relation_classification_event_append_only_truncate')
     -- Trin 5b 2b-i (spec §4.1): unikhed pr. fortolkning og tilstand; de to gamle regler er væk.
     OR NOT EXISTS (SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid
                     WHERE c.relname='interpretation_promotion_one_family_per_state'
                       AND i.indrelid='private.interpretation_promotion'::regclass AND i.indisunique
                       AND pg_get_expr(i.indpred,i.indrelid) LIKE '%target_type%=%family%')
     OR NOT EXISTS (SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid
                     WHERE c.relname='interpretation_promotion_one_target_per_interpretation'
                       AND i.indrelid='private.interpretation_promotion'::regclass AND i.indisunique
                       AND pg_get_expr(i.indpred,i.indrelid) LIKE '%target_type%<>%family%')
     OR EXISTS (SELECT 1 FROM pg_class WHERE relname='interpretation_promotion_one_family_per_interpretation')
     OR EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='private.interpretation_promotion'::regclass AND contype='u')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='private.interpretation_promotion'::regclass
                     AND conname='interpretation_promotion_family_state_check' AND convalidated)
     -- Trin 5b 2b-i (spec §5.4): klassifikationen ordinal_beholdt
     OR (SELECT pg_get_constraintdef(oid) FROM pg_constraint
          WHERE conrelid='private.relation_classification_event'::regclass AND conname='relation_classification_event_kind_check')
        IS DISTINCT FROM 'CHECK ((classification = ANY (ARRAY[''ordinal_afvigelse''::text, ''ordinal_beholdt''::text])))'
     OR to_regprocedure('private.relation_binding_state(uuid)') IS NULL
     OR to_regprocedure('private.relation_binding_state_sha256(uuid)') IS NULL
     OR to_regprocedure('private.append_relation_classification(uuid,text,jsonb)') IS NULL
     OR has_function_privilege('authenticated','private.relation_binding_state(uuid)','EXECUTE')
     OR has_function_privilege('anon','private.relation_binding_state(uuid)','EXECUTE')
     OR has_function_privilege('authenticated','private.append_relation_classification(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('anon','private.relation_binding_state_sha256(uuid)','EXECUTE')
     OR has_function_privilege('authenticated','private.relation_binding_state_sha256(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'RELATION_BINDING_STATE_CONTRACT_INVALID';
  END IF;
  FOREACH v_t IN ARRAY ARRAY['identity_control_exclusion','identity_control_parent_card','identity_control_parent_event'] LOOP
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=format('private.%I',v_t)::regclass) THEN
      RAISE EXCEPTION 'RELATION_BINDING_STATE_CONTRACT_INVALID: % uden RLS', v_t;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: 5b 2a — bindingens tilstand og klassifikationer';
END $relation_binding_state_verify$;

-- Trin 5b 2b-i (spec §5.1): arkets projektion er privat og uden grants.
DO $spouse_projection_verify$
BEGIN
  IF to_regprocedure('private.spouse_exception_projection(bigint)') IS NULL
     OR has_function_privilege('anon','private.spouse_exception_projection(bigint)','EXECUTE')
     OR has_function_privilege('authenticated','private.spouse_exception_projection(bigint)','EXECUTE')
     OR has_function_privilege('service_role','private.spouse_exception_projection(bigint)','EXECUTE')
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid='private.spouse_exception_projection(bigint)'::regprocedure) THEN
    RAISE EXCEPTION 'SPOUSE_EXCEPTION_PROJECTION_CONTRACT_INVALID';
  END IF;
END $spouse_projection_verify$;

-- Trin 5b del 2a (#151, spec §4.4): relationsbindingens flade og replay-kolonnen.
DO $relation_promotion_verify$
DECLARE f text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='private' AND table_name='interpretation_promotion_batch'
                  AND column_name='items_sha256' AND data_type='text' AND is_nullable='YES')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='private.interpretation_promotion_batch'::regclass
                     AND contype='c' AND pg_get_constraintdef(oid) LIKE '%items_sha256%^[0-9a-f]{64}$%')
     OR to_regprocedure('private.relation_decision_set(bigint)') IS NULL
     OR has_function_privilege('anon','private.relation_decision_set(bigint)','EXECUTE')
     OR has_function_privilege('authenticated','private.relation_decision_set(bigint)','EXECUTE')
     OR to_regprocedure('private.preview_relation_promotions(bigint,jsonb,boolean)') IS NULL
     OR has_function_privilege('anon','private.preview_relation_promotions(bigint,jsonb,boolean)','EXECUTE')
     OR has_function_privilege('authenticated','private.preview_relation_promotions(bigint,jsonb,boolean)','EXECUTE') THEN
    RAISE EXCEPTION 'RELATION_PROMOTION_CONTRACT_INVALID';
  END IF;
  FOREACH f IN ARRAY ARRAY['public.red_preview_relation_promotions(bigint,jsonb)',
                           'public.red_promote_relation_interpretations_batch(bigint,jsonb,text)',
                           'public.red_preview_relation_decisions(bigint)',
                           'public.red_decide_relation_interpretations(bigint,text)'] LOOP
    IF to_regprocedure(f) IS NULL
       OR NOT (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure(f))
       OR NOT has_function_privilege('authenticated',f,'EXECUTE')
       OR has_function_privilege('anon',f,'EXECUTE') THEN
      RAISE EXCEPTION 'RELATION_PROMOTION_CONTRACT_INVALID: %', f;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: 5b 2a — relationsbindingens flade';
END $relation_promotion_verify$;

-- Trin 5b del 2a (#151, spec §5.1): public_family_sources er en smal, gatet offentlig læseflade.
DO $family_sources_verify$
DECLARE v_def text; f regprocedure:=to_regprocedure('public.public_family_sources(bigint[])');
BEGIN
  IF f IS NULL THEN RAISE EXCEPTION 'FAMILY_SOURCES_CONTRACT_INVALID: mangler'; END IF;
  v_def:=pg_get_functiondef(f);
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=f)
     OR (SELECT proconfig FROM pg_proc WHERE oid=f) IS DISTINCT FROM ARRAY['search_path=pg_catalog']
     OR pg_get_function_result(f) IS DISTINCT FROM
        'TABLE(family_id bigint, slags text, counterpart_person_id bigint, source_record_ref uuid, source_label text, record_label text, citation_label text)'
     OR strpos(v_def,'person_daa_narrative_publication_allowed')=0
     OR strpos(v_def,'family_offentlig')=0
     OR strpos(v_def,'relation_binding_state')=0
     OR strpos(v_def,'narrative_record_contract_version()')=0
     OR NOT has_function_privilege('anon',f,'EXECUTE')
     OR NOT has_function_privilege('authenticated',f,'EXECUTE')
     OR EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid=f AND a.grantee=0)
     OR (EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role')
         AND has_function_privilege('service_role',f,'EXECUTE')) THEN
    RAISE EXCEPTION 'FAMILY_SOURCES_CONTRACT_INVALID';
  END IF;
  RAISE NOTICE 'OK: 5b 2a — public_family_sources';
END $family_sources_verify$;

-- Trin 5b 2b-ii (spec §4): family.id er identity, og sekvensen ligger ikke bag max(id).
DO $verify_family_id$
DECLARE v_seq text; v_last bigint; v_called boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='family'
                  AND column_name='id' AND is_identity='YES') THEN RAISE EXCEPTION 'VERIFY_FAMILY_ID_IDENTITY'; END IF;
  v_seq:=pg_get_serial_sequence('public.family','id');
  EXECUTE format('SELECT last_value,is_called FROM %s',v_seq) INTO v_last,v_called;
  IF (SELECT coalesce(max(id),0) FROM public.family) > (CASE WHEN v_called THEN v_last ELSE v_last-1 END) THEN
    RAISE EXCEPTION 'VERIFY_FAMILY_ID_SEQUENCE_BEHIND';
  END IF;
  RAISE NOTICE 'OK: 5b 2b-ii — family.id identity';
END $verify_family_id$;

-- RED-8 (review-handling A3, fund 1b-01): alle 25 bigint-id-tabeller er identity, og ingen sekvens ligger
-- bag max(id). Samme form som family-blokken ovenfor; en loader, der sætter eksplicitte id'er uden at
-- synke sekvensen bagefter, ville ellers give duplicate key ved næste DEFAULT-insert.
DO $verify_red8_id$
DECLARE t text; v_seq text; v_last bigint; v_called boolean; v_max bigint;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'assertion','change_event','change_set','citation','coat_of_arms',
    'conclusion','estate','fact','family','feed_pin','haendelse',
    'historical_event','lineage','media','media_variant','narrative','note',
    'organisation','person','place','relation','repository','source',
    'story','story_kilde'] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=t
                    AND column_name='id' AND data_type='bigint' AND is_identity='YES') THEN
      RAISE EXCEPTION 'VERIFY_RED8_ID_IDENTITY: %', t;
    END IF;
    v_seq:=pg_get_serial_sequence(format('public.%I',t),'id');
    EXECUTE format('SELECT last_value,is_called FROM %s',v_seq) INTO v_last,v_called;
    EXECUTE format('SELECT coalesce(max(id),0) FROM public.%I',t) INTO v_max;
    IF v_max > (CASE WHEN v_called THEN v_last ELSE v_last-1 END) THEN
      RAISE EXCEPTION 'VERIFY_RED8_ID_SEQUENCE_BEHIND: % (max % > sekvens %)', t, v_max,
        CASE WHEN v_called THEN v_last ELSE v_last-1 END;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: RED-8 — 25 id-tabeller er identity, ingen sekvens bag max(id)';
END $verify_red8_id$;

-- Trin 5b 2b-ii runde 2 (spec §17.7): profil v3 og titellisten.
DO $verify_relation_v3$
BEGIN
  IF to_regprocedure('private.relation_title_words()') IS NULL OR to_regprocedure('private.relation_name_has_title(text)') IS NULL
     OR NOT private.relation_name_has_title('Ida komtesse Dal') OR private.relation_name_has_title('Eva von Fik') THEN
    RAISE EXCEPTION 'VERIFY_RELATION_TITLE_WORDS';
  END IF;
  -- Trin 6d-3 (plan Task 2, Codex plan-fund 5): v3 er en form i profildata; writeren slår profilen op og bærer ingen
  -- profilnavne. Profilrækkerne kontrolleres i $verify_relation_persona_profile$ nedenfor.
  IF position('relation_persona_profile' IN pg_get_functiondef('private.write_relation_persona(uuid,text,jsonb)'::regprocedure))=0
     OR position('RELATION_PERSONA_PROFILE_INVALID' IN pg_get_functiondef('private.write_relation_persona(uuid,text,jsonb)'::regprocedure))=0
     OR position('relation-persona-2018-20' IN pg_get_functiondef('private.write_relation_persona(uuid,text,jsonb)'::regprocedure))>0
     OR position('RELATION_PERSON_CREATE_NAME_TITLE' IN pg_get_functiondef('private.write_relation_person_create(uuid,text,jsonb)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'VERIFY_RELATION_V3_WRITERS';
  END IF;
  RAISE NOTICE 'OK: 5b 2b-ii runde 2 — titelliste og writer v3';
END $verify_relation_v3$;

-- Trin 6d-3 (spec §5.1.1): relationsprofilerne er data. Tabellen er privat og låst til de tre prædikater og tre
-- former; findes en seed-kilde, står dens profiler med netop de aftalte former og tekstform (en frisk base har
-- hverken kilde 1 eller 3, og seeds indsættes kun, når kilden findes).
DO $verify_relation_persona_profile$
DECLARE r record; v_role text;
BEGIN
  IF to_regclass('private.relation_persona_profile') IS NULL
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private.relation_persona_profile'::regclass)
     OR (SELECT array_agg(a.attname::text ORDER BY a.attnum) FROM pg_index i
           JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey)
          WHERE i.indrelid='private.relation_persona_profile'::regclass AND i.indisprimary)
        IS DISTINCT FROM ARRAY['profile','source_id'] THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6d-3 relationsprofiltabel';
  END IF;
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_table_privilege(v_role,'private.relation_persona_profile','SELECT,INSERT,UPDATE,DELETE') THEN
      RAISE EXCEPTION 'VERIFY_FAILED: 6d-3 relationsprofiler tabeladgang %',v_role;
    END IF;
  END LOOP;
  FOR r IN SELECT * FROM (VALUES
      ('relation-persona-2018-20-v1',1::bigint,'{"relation.marriage":"v1","relation.child":"v1","relation.parent":"v1"}'::jsonb,'folded'),
      ('relation-persona-2018-20-v2',1::bigint,'{"relation.marriage":"v2"}'::jsonb,'folded'),
      ('relation-persona-2018-20-v3',1::bigint,'{"relation.marriage":"v3"}'::jsonb,'folded'),
      ('relation-persona-1939-v1',3::bigint,'{"relation.marriage":"v3","relation.parent":"v1"}'::jsonb,'raw'))
      AS v(profile,source_id,predicate_forms,text_form)
  LOOP
    IF EXISTS (SELECT 1 FROM public.source WHERE id=r.source_id)
       AND NOT EXISTS (SELECT 1 FROM private.relation_persona_profile pp
                        WHERE pp.profile=r.profile AND pp.source_id=r.source_id
                          AND pp.predicate_forms=r.predicate_forms AND pp.text_form=r.text_form) THEN
      RAISE EXCEPTION 'VERIFY_FAILED: 6d-3 relationsprofil % for kilde %',r.profile,r.source_id;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: 6d-3 relationsprofiler (tabel, adgang, seeds for de kilder, basen har)';
END $verify_relation_persona_profile$;

-- #244 (spec §7.1-§7.2, §5): rettelsestabellen er låst, origin-constraintet har tre værdier, og funktionerne findes.
DO $verify_244$
DECLARE r text;
BEGIN
  IF to_regclass('private.marriage_ordinal_correction') IS NULL
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private.marriage_ordinal_correction'::regclass)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.marriage_ordinal_correction'::regclass
                     AND tgname='trg_marriage_ordinal_correction_append_only')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.marriage_ordinal_correction'::regclass
                     AND tgname='trg_marriage_ordinal_correction_no_truncate') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 244 rettelsestabel';
  END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_table_privilege(r,'private.marriage_ordinal_correction','SELECT,INSERT,UPDATE,DELETE') THEN
      RAISE EXCEPTION 'VERIFY_FAILED: 244 tabeladgang %',r;
    END IF;
  END LOOP;
  IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='private.interpretation_party'::regclass
       AND conname='interpretation_party_origin_check') LIKE ALL (ARRAY['%relation_persona%','%relation_decision%','%ordinal_correction%'])
     IS NOT TRUE THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 244 origin-constraint';
  END IF;
  IF to_regprocedure('private.relation_book_ordinal(text)') IS NULL OR private.relation_book_ordinal('g. 2° m. X')<>2
     OR position('relation_ordered_windows' IN pg_get_functiondef('private.relation_marriage_ordinals(uuid)'::regprocedure))=0
     OR position('ORDINAL_BOOK_MISMATCH' IN pg_get_functiondef('private.write_relation_persona(uuid,text,jsonb)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 244 funktioner';
  END IF;
  RAISE NOTICE 'OK: #244 — ægteskabsnummer, bognummer, rettelsestabel';
END $verify_244$;

-- #248 rute A (spec §3.1-§3.3): genåbningstabellen er låst, RPC'en findes, og vagten mod dobbeltmål står i tilstanden.
DO $verify_248$
DECLARE r text;
BEGIN
  IF to_regclass('private.relation_reopen') IS NULL
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private.relation_reopen'::regclass)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.relation_reopen'::regclass
                     AND tgname='trg_relation_reopen_append_only')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.relation_reopen'::regclass
                     AND tgname='trg_relation_reopen_no_truncate') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 248 genåbningstabel';
  END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_table_privilege(r,'private.relation_reopen','SELECT,INSERT,UPDATE,DELETE') THEN
      RAISE EXCEPTION 'VERIFY_FAILED: 248 tabeladgang %',r;
    END IF;
  END LOOP;
  IF to_regprocedure('public.red_genaabn_relation_interpretation(uuid,integer,text,jsonb)') IS NULL
     OR position('v_rivals' IN pg_get_functiondef('private.relation_binding_state(uuid)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 248 funktioner';
  END IF;
  RAISE NOTICE 'OK: #248 — genåbning ved familieskift, vagt mod dobbeltmål';
END $verify_248$;

-- #150 trin 5c-1 (spec §4.3): legacy-ledgeren er låst, skrivefunktionerne er private, og slaegt versioneres.
DO $verify_150_ledger$
DECLARE r text; f text;
BEGIN
  IF to_regclass('private.legacy_placement_disposition') IS NULL
     OR to_regclass('private.legacy_placement_disposition_current') IS NULL
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private.legacy_placement_disposition'::regclass)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.legacy_placement_disposition'::regclass
                     AND tgname='trg_legacy_placement_disposition_append_only')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.legacy_placement_disposition'::regclass
                     AND tgname='trg_legacy_placement_disposition_no_truncate') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 150 ledger-tabel';
  END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_table_privilege(r,'private.legacy_placement_disposition','SELECT,INSERT,UPDATE,DELETE')
       OR has_table_privilege(r,'private.legacy_placement_disposition_current','SELECT') THEN
      RAISE EXCEPTION 'VERIFY_FAILED: 150 tabeladgang %',r;
    END IF;
    FOREACH f IN ARRAY ARRAY['private.legacy_external_id_sha256(bigint,bigint)','private.header_observation_uuid(uuid,text,integer)',
        'private.write_header_evidence(bigint,uuid,jsonb,jsonb)','private.write_record_placement(uuid,bigint,jsonb,uuid,jsonb)',
        'private.write_persona_placement(uuid,uuid,uuid,jsonb)','private.record_legacy_disposition(bigint,bigint,text,uuid,jsonb)',
        'private.lineage_of_entry(bigint)'] LOOP
      IF to_regprocedure(f) IS NULL THEN RAISE EXCEPTION 'VERIFY_FAILED: 150 mangler %',f; END IF;
      IF has_function_privilege(r,f,'EXECUTE') THEN RAISE EXCEPTION 'VERIFY_FAILED: 150 % eksekverbar for %',f,r; END IF;
    END LOOP;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM version_pk_registry WHERE tabel='slaegt')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.slaegt'::regclass AND tgname='trg_log_slaegt') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 150 slaegt versioneres ikke';
  END IF;
  FOREACH f IN ARRAY ARRAY['private.membership_state(uuid)','private.membership_is_current(bigint,bigint)',
      'private.placement_membership_not_current()','private.placement_membership_set(bigint)'] LOOP
    IF to_regprocedure(f) IS NULL OR has_function_privilege('authenticated',f,'EXECUTE') THEN
      RAISE EXCEPTION 'VERIFY_FAILED: 150 membership-funktion %',f;
    END IF;
  END LOOP;
  -- Trin 6d-1 (B6 afledt): komponenttilstanden er privat; ingen API-rolle må kalde den.
  IF to_regprocedure('private.membership_component_states()') IS NULL THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6d-1 mangler private.membership_component_states()';
  END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r,'private.membership_component_states()','EXECUTE') THEN
      RAISE EXCEPTION 'VERIFY_FAILED: 6d-1 membership_component_states eksekverbar for %',r;
    END IF;
  END LOOP;
  -- Trin 6d-2a: oversigtsreglen er privat; ingen API-rolle må kalde den.
  IF to_regprocedure('private.overview_mention_narratives(bigint[])') IS NULL THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6d-2a mangler private.overview_mention_narratives(bigint[])';
  END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r,'private.overview_mention_narratives(bigint[])','EXECUTE') THEN
      RAISE EXCEPTION 'VERIFY_FAILED: 6d-2a overview_mention_narratives eksekverbar for %',r;
    END IF;
  END LOOP;
  -- Trin 6d-2a: redaktørens læsning af oversigtsomtaler: kun authenticated (rollegaten i kroppen).
  IF to_regprocedure('public.red_overview_mentions(bigint[])') IS NULL THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6d-2a mangler public.red_overview_mentions(bigint[])';
  END IF;
  IF has_function_privilege('anon','public.red_overview_mentions(bigint[])','EXECUTE')
     OR has_function_privilege('service_role','public.red_overview_mentions(bigint[])','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_overview_mentions(bigint[])','EXECUTE') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6d-2a red_overview_mentions ACL';
  END IF;
  -- Trin 6d-2a: retningsreglen i samme_som er privat; ingen API-rolle må kalde den.
  IF to_regprocedure('private.samme_som_data_direction(bigint,bigint)') IS NULL THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6d-2a mangler private.samme_som_data_direction(bigint,bigint)';
  END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r,'private.samme_som_data_direction(bigint,bigint)','EXECUTE') THEN
      RAISE EXCEPTION 'VERIFY_FAILED: 6d-2a samme_som_data_direction eksekverbar for %',r;
    END IF;
  END LOOP;
  -- Helbred (spec §4.4): promoverede memberships, hvis tilstand er ændret siden; 5c-2's læsere filtrerer på gældende.
  RAISE NOTICE 'PLACEMENT_MEMBERSHIP_NOT_CURRENT n=%',private.placement_membership_not_current();
  RAISE NOTICE 'OK: #150 — legacy-ledger, private placement-skrivefunktioner, slaegt versioneret';
END $verify_150_ledger$;

-- ===== Review trin B (1d.3b-01): accepterede, ubundne relationer hvis familie er skiftet siden afgørelsen =====
-- Kun en måling (NOTICE), aldrig en fejl: tæller accepterede, gældende relation.marriage/relation.parent uden
-- familiebinding, hvis bindingstilstand findes og peger på en anden familie end decision_evidence->>'family_id'
-- (også manglende family_id). Sådanne afvises nu ved førstebinding (RELATION_PROMOTION_DECISION_FAMILY_CHANGED)
-- og kræver en ny afgørelse. Forventet: 0.
DO $verify_trin_b_decision_family$
DECLARE n bigint;
BEGIN
  SELECT count(*) INTO n
    FROM private.interpretation_current ic
    CROSS JOIN LATERAL (SELECT private.relation_binding_state(ic.id) AS st) s
   WHERE ic.status='accepted' AND ic.predicate IN ('relation.marriage','relation.parent')
     AND NOT EXISTS (SELECT 1 FROM private.interpretation_promotion p WHERE p.interpretation_id=ic.id AND p.target_type='family')
     AND s.st IS NOT NULL
     AND (s.st#>>'{family,family_id}')::bigint IS DISTINCT FROM (ic.decision_evidence->>'family_id')::bigint;
  RAISE NOTICE 'TRIN_B_DECISION_FAMILY_CHANGED_UNBOUND n=% (forventet 0)',n;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'TRIN_B_DECISION_FAMILY_CHANGED_UNBOUND kunne ikke måles: %',SQLERRM;
END $verify_trin_b_decision_family$;

-- ===== Trin 6b: commit-vagten for publication_identity og reimport_event's partielle indekser =====
-- Den udskudte constraint trigger (Codex 6B-01, controller): findes på private.reimport_event, er DEFERRABLE INITIALLY
-- DEFERRED, filtrerer på operation og kalder den private SECURITY DEFINER-funktion, som ingen klientrolle kan kalde.
-- De to partielle indekser bærer køvagtens og finalize's opslag.
DO $verify_6b_commit_guard$
DECLARE v_t record; f text:='private.require_publication_identity_finalized()';
BEGIN
  SELECT t.tgdeferrable,t.tginitdeferred,t.tgfoid,t.tgconstraint,t.tgenabled,pg_get_triggerdef(t.oid) AS def INTO v_t
    FROM pg_trigger t
   WHERE t.tgrelid='private.reimport_event'::regclass AND t.tgname='trg_reimport_event_publication_identity_finalized';
  IF NOT FOUND OR to_regprocedure(f) IS NULL OR v_t.tgfoid<>to_regprocedure(f) OR v_t.tgconstraint=0
     OR NOT v_t.tgdeferrable OR NOT v_t.tginitdeferred OR v_t.tgenabled<>'O'
     OR position('AFTER INSERT ON private.reimport_event' IN v_t.def)=0
     OR position('WHEN ((new.operation = ''publication_identity''::text))' IN v_t.def)=0 THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6b commit-vagt trg_reimport_event_publication_identity_finalized %',coalesce(v_t.def,'mangler');
  END IF;
  IF NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid=to_regprocedure(f))
     OR has_function_privilege('anon',f,'EXECUTE') OR has_function_privilege('authenticated',f,'EXECUTE')
     OR has_function_privilege('service_role',f,'EXECUTE') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6b commit-vagtens funktion (security definer/ACL)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid
                  WHERE i.indrelid='private.reimport_event'::regclass AND c.relname='reimport_event_publication_persona_receipt_idx'
                    AND pg_get_expr(i.indpred,i.indrelid)='(operation = ''publication_persona''::text)'
                    AND pg_get_indexdef(i.indexrelid) LIKE '%((payload -> ''result_receipt''::text) ->> ''source_persona_id''::text)%')
     OR NOT EXISTS (SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid
                     WHERE i.indrelid='private.reimport_event'::regclass AND c.relname='reimport_event_publication_identity_batch_idx'
                       AND pg_get_expr(i.indpred,i.indrelid)='(operation = ''publication_identity''::text)'
                       AND pg_get_indexdef(i.indexrelid) LIKE '%(payload ->> ''persona_batch_id''::text)%') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6b partielle indekser på reimport_event';
  END IF;
  RAISE NOTICE 'OK: trin 6b — commit-vagt (udskudt, operationsfiltreret) og partielle indekser på reimport_event';
END $verify_6b_commit_guard$;

-- ===== Trin 6b opfølgning (I2): C kan genkøres efter fortrydelse =====
-- Hjælperen for en fortrudt publikationsidentitet er privat (SECURITY DEFINER, ingen klientrolle kan kalde den), og de seks
-- steder, der behandler den som »ingen identitet« eller godtager dens version (kernen, køvagten, stikprøvens population,
-- finalize, writeren og kontrollen), bruger den. En gammel definition (fx efter en delvis restore) ville give webkø-adfærden
-- tilbage eller lade C afvise genkørslen. Hjælperens adfærd prøves uden skrivning (db-verify kører også i prod, hvor en
-- skrivende probe ville flytte sekvenser): kroppen skal bære definitionens led, og den skal være falsk for en ukendt persona
-- og for enhver identitet, der ikke er superseded. En udvandet hjælper (fx RETURN true eller RETURN false) fejler.
DO $verify_6b_rerun$
DECLARE f text:='private.publication_identity_reverted(uuid)'; v_fn text; v_src text; v_led text;
BEGIN
  IF to_regprocedure(f) IS NULL OR NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid=to_regprocedure(f))
     OR has_function_privilege('anon',f,'EXECUTE') OR has_function_privilege('authenticated',f,'EXECUTE')
     OR has_function_privilege('service_role',f,'EXECUTE') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6b fortrudt publikationsidentitet: hjælperen (findes/security definer/ACL)';
  END IF;
  SELECT p.prosrc INTO v_src FROM pg_proc p WHERE p.oid=to_regprocedure(f);
  FOREACH v_led IN ARRAY ARRAY['i.decision_status=''superseded''','cb.status=''reversed''','c.operation=''publication_identity''',
                               'c.element_id=''publication-identity:''||p_persona::text',
                               'c.payload->''result_receipt''->>''identity_version''=(v_i.version-1)::text',
                               'r.operation=''reversal''','r.element_id LIKE ''publication-identity-reversal:%''',
                               'ev.version=v_i.version','ev.evidence=v_i.evidence'] LOOP
    IF position(v_led IN v_src)=0 THEN
      RAISE EXCEPTION 'VERIFY_FAILED: 6b fortrudt publikationsidentitet: hjælperen mangler leddet %',v_led;
    END IF;
  END LOOP;
  IF private.publication_identity_reverted('00000000-0000-0000-0000-000000000000'::uuid)
     OR EXISTS (SELECT 1 FROM private.source_persona_identity i
                 WHERE i.decision_status<>'superseded' AND private.publication_identity_reverted(i.source_persona_id)) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6b fortrudt publikationsidentitet: hjælperen er sand for en ukendt eller ikke-superseded persona';
  END IF;
  -- I2-review P1: de to partielle indekser, som køvagtens og hjælperens opslag bruger (webkøen kalder køvagten pr. persona)
  IF NOT EXISTS (SELECT 1 FROM pg_index x JOIN pg_class c ON c.oid=x.indexrelid
                  WHERE x.indrelid='private.reimport_event'::regclass AND c.relname='reimport_event_publication_identity_batch_pair_idx'
                    AND pg_get_expr(x.indpred,x.indrelid)='(operation = ''publication_identity''::text)'
                    AND pg_get_indexdef(x.indexrelid) LIKE '%(((payload ->> ''persona_batch_id''::text)), batch_id)%')
     OR NOT EXISTS (SELECT 1 FROM pg_index x JOIN pg_class c ON c.oid=x.indexrelid
                     WHERE x.indrelid='private.reimport_event'::regclass AND c.relname='reimport_event_reversal_batch_idx'
                       AND pg_get_expr(x.indpred,x.indrelid)='(operation = ''reversal''::text)'
                       AND pg_get_indexdef(x.indexrelid) LIKE '%(batch_id)%') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6b fortrudt publikationsidentitet: køvagtens/hjælperens partielle indekser';
  END IF;
  FOREACH v_fn IN ARRAY ARRAY['private.decide_source_persona_identity(uuid,bigint,integer,text,jsonb,text)',
                              'private.persona_awaiting_control(uuid)','private.publication_sample_candidates(uuid)',
                              'private.verify_publication_identity_input(uuid)','private.write_publication_identity(uuid,text,jsonb)',
                              'public.red_publication_control(uuid)'] LOOP
    IF to_regprocedure(v_fn) IS NULL
       OR position('private.publication_identity_reverted(' IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid=to_regprocedure(v_fn)))=0 THEN
      RAISE EXCEPTION 'VERIFY_FAILED: 6b fortrudt publikationsidentitet: % bruger ikke hjælperen',v_fn;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: trin 6b — fortrudt publikationsidentitet (hjælper privat og prøvet; kerne, køvagt, stikprøve, finalize, writer, kontrol; indekser)';
END $verify_6b_rerun$;

-- ===== Trin 6c-1 retning 2: de automatiske udfald (delspec 6c-1 §4.8) =====
-- Hjælperen for de automatiske udfald (enig, svag, ingen_kandidat) findes, er SECURITY DEFINER med search_path og kan ikke
-- kaldes af nogen klientrolle; den gamle enige-hjælper findes ikke længere.
DO $verify_6c1_retning2$
DECLARE f text:='private.publication_control_auto(uuid,uuid)';
BEGIN
  IF to_regprocedure(f) IS NULL OR NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid=to_regprocedure(f))
     OR NOT EXISTS (SELECT 1 FROM pg_proc p, unnest(p.proconfig) c WHERE p.oid=to_regprocedure(f) AND c LIKE 'search_path=%')
     OR has_function_privilege('anon',f,'EXECUTE') OR has_function_privilege('authenticated',f,'EXECUTE')
     OR has_function_privilege('service_role',f,'EXECUTE') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6c-1 retning 2: % (findes/security definer/search_path/ACL)',f;
  END IF;
  IF to_regprocedure('private.publication_control_enig(uuid,uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6c-1 retning 2: private.publication_control_enig findes stadig';
  END IF;
  RAISE NOTICE 'OK: trin 6c-1 retning 2 — publication_control_auto privat, publication_control_enig fjernet';
END $verify_6c1_retning2$;

-- ===== Trin 6c-2b: påstandsnøglet rettelse (spec 2026-11-02 §4.5) =====
-- Journalen findes med RLS og uden klientadgang; de delte regler er private; RPC'erne er SECURITY DEFINER med
-- search_path og kun for authenticated (rollegaten er inde i dem).
DO $verify_6c2b_paastand$
DECLARE v_role text; v_priv text; f text;
BEGIN
  IF to_regclass('public.paastand_korrektion') IS NULL
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.paastand_korrektion'::regclass) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6c-2b paastand_korrektion mangler eller har ikke RLS';
  END IF;
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    FOREACH v_priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE'] LOOP
      IF has_table_privilege(v_role,'public.paastand_korrektion',v_priv) THEN
        RAISE EXCEPTION 'VERIFY_FAILED: 6c-2b paastand_korrektion: % har %',v_role,v_priv;
      END IF;
    END LOOP;
  END LOOP;
  FOREACH f IN ARRAY ARRAY['private.saml_blanktegn_v1(text)','private.navn_forkortes(text,text)'] LOOP
    IF to_regprocedure(f) IS NULL
       OR has_function_privilege('anon',f,'EXECUTE') OR has_function_privilege('authenticated',f,'EXECUTE') THEN
      RAISE EXCEPTION 'VERIFY_FAILED: 6c-2b %: findes/ACL',f;
    END IF;
  END LOOP;
  FOREACH f IN ARRAY ARRAY['public.red_ret_paastand(bigint,jsonb,text,uuid,jsonb)',
                           'public.red_paastand_historik(bigint)',
                           'public.red_ret_ocr_paastand(bigint,jsonb,jsonb)'] LOOP
    IF to_regprocedure(f) IS NULL OR NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid=to_regprocedure(f))
       OR NOT EXISTS (SELECT 1 FROM pg_proc p, unnest(p.proconfig) c WHERE p.oid=to_regprocedure(f) AND c LIKE 'search_path=%')
       OR has_function_privilege('anon',f,'EXECUTE') OR NOT has_function_privilege('authenticated',f,'EXECUTE') THEN
      RAISE EXCEPTION 'VERIFY_FAILED: 6c-2b %: findes/security definer/search_path/ACL',f;
    END IF;
  END LOOP;
  IF private.saml_blanktegn_v1(E'12.\u00a0marts\n1702 ') IS DISTINCT FROM '12. marts 1702'
     OR private.navn_forkortes('Ditlev Reventlow til X','Ditlev') IS NOT TRUE
     OR private.navn_forkortes('Ditlev','Ditlev') IS NOT FALSE THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6c-2b blanktegns- eller navneregel';
  END IF;
  RAISE NOTICE 'OK: trin 6c-2b — paastand_korrektion (RLS, ingen klientadgang), regler private, RPC''er kun authenticated';
END $verify_6c2b_paastand$;

-- ===== dato-markoer-v2: markør pr. prædikat =====
-- Regelfunktionen findes, er IMMUTABLE og kan ikke kaldes af nogen klientrolle; red_normaliser_forslag er stadig
-- SECURITY DEFINER og kun for authenticated.
DO $verify_markoer_v2$
DECLARE f text:='private.normaliser_dato_markoer_v2(text,text)'; g text:='public.red_normaliser_forslag(uuid,integer,text)';
BEGIN
  IF to_regprocedure(f) IS NULL OR (SELECT p.provolatile FROM pg_proc p WHERE p.oid=to_regprocedure(f))<>'i'
     OR NOT EXISTS (SELECT 1 FROM pg_proc p, unnest(p.proconfig) c WHERE p.oid=to_regprocedure(f) AND c LIKE 'search_path=%')
     OR has_function_privilege('anon',f,'EXECUTE') OR has_function_privilege('authenticated',f,'EXECUTE')
     OR has_function_privilege('service_role',f,'EXECUTE') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: dato-markoer-v2 %: findes/immutable/search_path/ACL',f;
  END IF;
  IF private.normaliser_dato_markoer_v2('* 1750','person.birth') IS DISTINCT FROM '1750'
     OR private.normaliser_dato_markoer_v2(E'\u2020 1750','person.death') IS DISTINCT FROM '1750'
     OR private.normaliser_dato_markoer_v2('* 1750','person.death') IS DISTINCT FROM '* 1750'
     OR private.normaliser_dato_markoer_v2('* og † 1756','person.birth') IS DISTINCT FROM '* og † 1756'
     OR private.normaliser_dato_markoer_v2('* 1750','person.name') IS NOT NULL THEN
    RAISE EXCEPTION 'VERIFY_FAILED: dato-markoer-v2 regel';
  END IF;
  IF to_regprocedure(g) IS NULL OR NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid=to_regprocedure(g))
     OR has_function_privilege('anon',g,'EXECUTE') OR NOT has_function_privilege('authenticated',g,'EXECUTE')
     OR has_function_privilege('service_role',g,'EXECUTE') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: dato-markoer-v2 %: ACL uændret',g;
  END IF;
  RAISE NOTICE 'OK: dato-markoer-v2 — regel private og IMMUTABLE, red_normaliser_forslag kun authenticated';
END $verify_markoer_v2$;

-- ===== Trin 6m-a: forslagsversion med menneskelig læsning =====
-- red_ret_forslag findes som SECURITY DEFINER med search_path og kun for authenticated (som red_normaliser_forslag);
-- triggerfunktionen er SECURITY DEFINER med search_path og kan ikke kaldes af nogen klientrolle; triggeren er en udskudt
-- constraint-trigger på private.interpretation. red_decide_interpretation afviser grundlaget menneske-laesning-v1: prøvet
-- med en midlertidig redaktør i en delttransaktion, der altid rulles tilbage (intet skrives; ingen sekvenser rykkes).
DO $verify_6ma$
DECLARE f text:='public.red_ret_forslag(uuid,integer,text,jsonb)'; t text:='private.kontroller_forslag_binding_v1()';
  v_actor uuid:='00000000-0000-4000-8000-0000006a0a99'; v_err text;
BEGIN
  IF to_regprocedure(f) IS NULL OR NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid=to_regprocedure(f))
     OR NOT EXISTS (SELECT 1 FROM pg_proc p, unnest(p.proconfig) c WHERE p.oid=to_regprocedure(f) AND c LIKE 'search_path=%')
     OR has_function_privilege('anon',f,'EXECUTE') OR NOT has_function_privilege('authenticated',f,'EXECUTE')
     OR has_function_privilege('service_role',f,'EXECUTE') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6m-a %: findes/security definer/search_path/ACL',f;
  END IF;
  IF to_regprocedure(t) IS NULL OR NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid=to_regprocedure(t))
     OR NOT EXISTS (SELECT 1 FROM pg_proc p, unnest(p.proconfig) c WHERE p.oid=to_regprocedure(t) AND c LIKE 'search_path=%')
     OR has_function_privilege('anon',t,'EXECUTE') OR has_function_privilege('authenticated',t,'EXECUTE')
     OR has_function_privilege('service_role',t,'EXECUTE') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6m-a %: findes/security definer/search_path/ACL',t;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger g WHERE g.tgrelid='private.interpretation'::regclass
                   AND g.tgname='interpretation_forslag_binding' AND g.tgconstraint<>0 AND g.tgdeferrable
                   AND g.tginitdeferred AND g.tgenabled<>'D' AND g.tgfoid=to_regprocedure(t)) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6m-a triggeren interpretation_forslag_binding (findes/udskudt/funktion)';
  END IF;
  BEGIN
    INSERT INTO auth.users(id,email) VALUES (v_actor,'verify-6ma@test.invalid') ON CONFLICT DO NOTHING;
    INSERT INTO public.profiles(id,rolle,navn,email) VALUES (v_actor,'redaktion','Verify 6ma','verify-6ma@test.invalid')
      ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    BEGIN
      PERFORM public.red_decide_interpretation(gen_random_uuid(),1,'accepted','{"basis":"menneske-laesning-v1"}');
    EXCEPTION WHEN OTHERS THEN v_err:=SQLERRM;
    END;
    RAISE EXCEPTION 'VERIFY_6MA_ROLLBACK';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'VERIFY_6MA_ROLLBACK' THEN RAISE; END IF;
  END;
  IF v_err IS NULL OR v_err NOT LIKE 'EVIDENCE_BASIS_RESERVED: menneske-laesning-v1%' THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6m-a red_decide_interpretation afviser ikke menneske-laesning-v1: %',v_err;
  END IF;
  RAISE NOTICE 'OK: trin 6m-a — red_ret_forslag kun authenticated, kontrolfunktion privat, trigger udskudt, grundlaget reserveret';
END $verify_6ma$;

-- Trin 6c-3a (spec 2026-11-07-trin6c3-a6b-resten-design.md §4.4 og §4.7 pkt. 4): afstemningskvitteringen er låst
-- (RLS, append-only- og no-truncate-trigger, ingen tabeladgang), har sin entydighed og revisionsreference, og writeren
-- er privat (security definer, fast search_path, ingen EXECUTE for anon/authenticated/service_role).
DO $verify_6c3a$
DECLARE r text; f text:='private.write_text_revision_reconciliation(uuid,jsonb,jsonb)';
BEGIN
  IF to_regclass('private.text_revision_reconciliation') IS NULL
     OR NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid='private.text_revision_reconciliation'::regclass),false)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.text_revision_reconciliation'::regclass
                     AND tgname='trg_text_revision_reconciliation_append_only'
                     AND tgfoid='private.reject_evidence_mutation()'::regprocedure)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.text_revision_reconciliation'::regclass
                     AND tgname='trg_text_revision_reconciliation_no_truncate'
                     AND tgfoid='private.reject_evidence_mutation()'::regprocedure) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6c-3a afstemningstabel';
  END IF;
  -- Hvert ben er NOT EXISTS (aldrig NULL): en manglende constraint fejler i stedet for at give et NULL-ben, der lader
  -- IF'en passere. pg_get_constraintdef udelader skemaet, når private er i search_path; begge former godtages.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='private.text_revision_reconciliation'::regclass
                  AND conname='text_revision_reconciliation_old_unique' AND contype='u'
                  AND pg_get_constraintdef(oid)='UNIQUE NULLS NOT DISTINCT (old_interpretation_key, old_promotion_id)')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='private.text_revision_reconciliation'::regclass
                     AND conname='text_revision_reconciliation_event_fk' AND contype='f'
                     AND pg_get_constraintdef(oid) IN (
                       'FOREIGN KEY (revision_batch_id, revision_element_id) REFERENCES reimport_event(batch_id, element_id)',
                       'FOREIGN KEY (revision_batch_id, revision_element_id) REFERENCES private.reimport_event(batch_id, element_id)'))
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='private.text_revision_reconciliation'::regclass AND contype='f'
                     AND pg_get_constraintdef(oid) IN (
                       'FOREIGN KEY (old_promotion_id) REFERENCES interpretation_promotion(id)',
                       'FOREIGN KEY (old_promotion_id) REFERENCES private.interpretation_promotion(id)'))
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='private.text_revision_reconciliation'::regclass AND contype='f'
                     AND pg_get_constraintdef(oid) IN (
                       'FOREIGN KEY (new_promotion_id) REFERENCES interpretation_promotion(id)',
                       'FOREIGN KEY (new_promotion_id) REFERENCES private.interpretation_promotion(id)'))
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='private.text_revision_reconciliation'::regclass
                     AND conname='text_revision_reconciliation_shape_check' AND contype='c'
                     AND pg_get_constraintdef(oid) LIKE '%ELSE false%') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6c-3a afstemningstabellens nøgler';
  END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_table_privilege(r,'private.text_revision_reconciliation','SELECT,INSERT,UPDATE,DELETE,TRUNCATE') THEN
      RAISE EXCEPTION 'VERIFY_FAILED: 6c-3a tabeladgang %',r;
    END IF;
  END LOOP;
  IF to_regprocedure(f) IS NULL OR NOT coalesce((SELECT p.prosecdef FROM pg_proc p WHERE p.oid=to_regprocedure(f)),false)
     OR NOT EXISTS (SELECT 1 FROM pg_proc p, unnest(p.proconfig) c WHERE p.oid=to_regprocedure(f) AND c LIKE 'search_path=%')
     OR has_function_privilege('anon',f,'EXECUTE') OR has_function_privilege('authenticated',f,'EXECUTE')
     OR has_function_privilege('service_role',f,'EXECUTE') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6c-3a %: findes/security definer/search_path/ACL',f;
  END IF;
  RAISE NOTICE 'OK: trin 6c-3a — afstemningskvitteringen er tilføj-kun og lukket, writeren er privat';
END $verify_6c3a$;

-- Redaktøren ser levende (decisions 2026-11-13, blokken redaktoer-ser-levende): de tre læse-RPC'er bag personsiden har
-- en redaktør-gren og beholder gæsternes gate; »offentlig«-hjælperne afhænger ikke af kalderen (de bærer gæsternes
-- policies); haendelse har det additive redaktion_read-lag.
-- Trin 6e-2: koordinat-RPC'en samler legacy- og placement-rækker i én FULL JOIN, så gæste-gaten står over
-- coalesce(x.person_id,pl.person_id); redaktør-grenen er den samme.
DO $verify_redaktoer_ser_levende$
DECLARE f regprocedure; v_def text; v_gate text;
BEGIN
  FOR f,v_gate IN SELECT to_regprocedure(x.sig),x.gate FROM (VALUES
      ('public.public_person_facts(bigint[])','public.entitet_offentlig(''person'',fa.subjekt_id)'),
      ('public.public_family_sources(bigint[])','public.family_offentlig(b.fam)'),
      ('public.public_person_source_coordinates()','public.entitet_offentlig(''person'',coalesce(x.person_id,pl.person_id))')) x(sig,gate) LOOP
    IF f IS NULL THEN RAISE EXCEPTION 'VERIFY_FAILED: redaktoer-ser-levende: en læse-RPC mangler'; END IF;
    v_def:=pg_get_functiondef(f);
    IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=f)
       OR (SELECT proconfig FROM pg_proc WHERE oid=f) IS DISTINCT FROM ARRAY['search_path=pg_catalog']
       OR strpos(v_def,'v_red boolean:=public.current_rolle()=''redaktion''')=0
       OR strpos(v_def,'(v_red OR '||v_gate||')')=0
       OR NOT has_function_privilege('anon',f,'EXECUTE')
       OR NOT has_function_privilege('authenticated',f,'EXECUTE')
       OR EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid=f AND a.grantee=0) THEN
      RAISE EXCEPTION 'VERIFY_FAILED: redaktoer-ser-levende %: redaktør-gren, gæste-gate, search_path eller ACL',f;
    END IF;
  END LOOP;
  FOR f IN SELECT to_regprocedure(s) FROM unnest(ARRAY['public.person_offentlig(bigint)',
      'public.family_offentlig(bigint)','public.entitet_offentlig(text,bigint)',
      'public.person_daa_narrative_publication_allowed(bigint)']) s LOOP
    IF f IS NULL OR strpos(pg_get_functiondef(f),'current_rolle')>0 THEN
      RAISE EXCEPTION 'VERIFY_FAILED: redaktoer-ser-levende: % mangler eller afhænger af kalderens rolle',f;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='haendelse'
                  AND policyname='redaktion_read' AND cmd='SELECT') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: redaktoer-ser-levende: haendelse mangler redaktion_read';
  END IF;
  RAISE NOTICE 'OK: redaktoer-ser-levende — redaktionen ser levende i fakta, familiekilder og koordinater; gæsternes gate uændret';
END $verify_redaktoer_ser_levende$;

-- trin 6e-2: sidekort og omregning PDF-side -> trykt side.
-- At source.sidekort er NULL for en given kilde er ingen invariant (ceremonien udfylder kortet); kun gyldigheden og kontrakten testes.
DO $verify_6e2_sidekort$
DECLARE
  f text; r text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='source' AND column_name='sidekort' AND data_type='jsonb') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6e-2 source.sidekort mangler';
  END IF;
  IF EXISTS (SELECT 1 FROM public.source WHERE sidekort IS NOT NULL AND NOT private.sidekort_gyldigt(sidekort)) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6e-2 ugyldigt sidekort på en kilde';
  END IF;
  FOREACH f IN ARRAY ARRAY['public.source_trykt_side(bigint,text)','public.side_trykt(public.citation)'] LOOP
    IF to_regprocedure(f) IS NULL OR (SELECT p.prosecdef FROM pg_proc p WHERE p.oid=to_regprocedure(f))
       OR NOT has_function_privilege('anon',f,'EXECUTE') OR NOT has_function_privilege('authenticated',f,'EXECUTE')
       OR EXISTS (SELECT 1 FROM pg_proc p, aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x WHERE p.oid=to_regprocedure(f) AND x.grantee=0) THEN
      RAISE EXCEPTION 'VERIFY_FAILED: 6e-2 % findes ikke / er DEFINER / forkert ACL', f;
    END IF;
  END LOOP;
  IF private.sidekort_gyldigt('[]'::jsonb) OR NOT private.sidekort_gyldigt(NULL)
     OR NOT private.sidekort_gyldigt('[{"pdf_fra":1,"pdf_til":2,"trykt_fra":5}]')
     OR private.sidekort_gyldigt('[{"pdf_fra":1,"pdf_til":3,"trykt_fra":5},{"pdf_fra":3,"pdf_til":4,"trykt_fra":9}]') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6e-2 sidekort_gyldigt kontrakt';
  END IF;
  IF position('source_trykt_side' IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.public_person_facts(bigint[])'::regprocedure))=0 THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6e-2 public_person_facts viser ikke trykt side';
  END IF;
  -- Kontrakt med NULL-kort og udfyldt fixture-kort (rulles tilbage), kaldt som anon.
  BEGIN
    INSERT INTO public.source(id,titel,sidekort) VALUES
      (-6291,'verify-sidekort',NULL),
      (-6292,'verify-sidekort','[{"pdf_fra":490,"pdf_til":545,"trykt_fra":1},{"pdf_fra":547,"pdf_til":548,"trykt_fra":57}]');
    SET LOCAL ROLE anon;
    IF public.source_trykt_side(-6291,'201-202') IS DISTINCT FROM '201-202'
       OR public.source_trykt_side(-6291,NULL) IS NOT NULL
       OR public.source_trykt_side(-6292,'541') IS DISTINCT FROM '52'
       OR public.source_trykt_side(-6292,'541-542') IS DISTINCT FROM '52-53'
       OR public.source_trykt_side(-6292,'546') IS NOT NULL
       OR public.source_trykt_side(-6292,'abc') IS NOT NULL THEN
      RAISE EXCEPTION 'VERIFY_FAILED: 6e-2 source_trykt_side kontrakt (anon)';
    END IF;
    -- side_trykt(citation) som anon, mod NULL-kort og udfyldt kort (række-literal: uafhængig af citation-RLS)
    IF public.side_trykt(ROW(-6291,NULL,-6291,'538',NULL,NULL,NULL)::public.citation) IS DISTINCT FROM '538'
       OR public.side_trykt(ROW(-6292,NULL,-6292,'538',NULL,NULL,NULL)::public.citation) IS DISTINCT FROM '49'
       OR public.side_trykt(ROW(-6292,NULL,-6292,'546',NULL,NULL,NULL)::public.citation) IS NOT NULL THEN
      RAISE EXCEPTION 'VERIFY_FAILED: 6e-2 side_trykt kontrakt (anon)';
    END IF;
    RESET ROLE;
    RAISE EXCEPTION 'VERIFY_6E2_ROLLBACK';
  EXCEPTION WHEN raise_exception THEN
    RESET ROLE;
    GET STACKED DIAGNOSTICS r = MESSAGE_TEXT;
    IF r <> 'VERIFY_6E2_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: trin 6e-2 — sidekort, omregning og anon-adgang';
END $verify_6e2_sidekort$;

-- Trin 6e-2 Task 2: etiketreglens funktioner og bindingens CHECK.
DO $verify_6e2_etiket$
DECLARE v_def text;
BEGIN
  IF to_regprocedure('private.linje_kode(text,text)') IS NULL
     OR to_regprocedure('private.record_key_uden_bognoegle(text)') IS NULL
     OR to_regprocedure('private.narrative_record_wanted_labels(uuid)') IS NULL THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6e-2 etiketfunktioner mangler';
  END IF;
  IF has_function_privilege('anon','private.narrative_record_wanted_labels(uuid)','EXECUTE')
     OR has_function_privilege('authenticated','private.narrative_record_wanted_labels(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6e-2 wanted_labels åben for klienter';
  END IF;
  IF private.linje_kode('IV. Den danske grevelige Linje af 1673.','IV') IS DISTINCT FROM 'IV'
     OR private.linje_kode('A. Den holstenske Linje.','Stamme-x') IS DISTINCT FROM 'A'
     OR private.linje_kode('Den grevelige linje af 1673','V') IS DISTINCT FROM 'V'
     OR private.record_key_uden_bognoegle('record-62000000-0000-4000-8000-0000000000a1') IS NOT TRUE
     OR private.record_key_uden_bognoegle('V-1') IS NOT FALSE THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6e-2 linje_kode / record_key_uden_bognoegle';
  END IF;
  -- CHECK tillader '' og afviser blanktegn.
  SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint
   WHERE conrelid='private.narrative_record_publication'::regclass
     AND conname='narrative_record_publication_record_label_check';
  IF v_def IS NULL OR v_def NOT LIKE '%record_label%=%''''%' THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6e-2 bindingens CHECK tillader ikke tom postdel';
  END IF;
  IF EXISTS (SELECT 1 WHERE NOT ('' = '' OR btrim('')<>''))
     OR NOT ((SELECT bool_and(v='' OR btrim(v)<>'') FROM (VALUES (''),('IV')) x(v)))
     OR ((SELECT bool_and(v='' OR btrim(v)<>'') FROM (VALUES ('  ')) x(v))) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6e-2 CHECK-semantik';
  END IF;
  v_def := pg_get_functiondef('private.validate_reimport_case_elements(jsonb,jsonb)'::regprocedure);
  IF v_def LIKE '%coalesce(btrim(v_payload->>''record_label''),'''')=''''%' THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6e-2 validatoren afviser stadig tom record_label';
  END IF;
  RAISE NOTICE 'OK: trin 6e-2 — etiketregel og tom postdel';
END $verify_6e2_etiket$;

-- Trin 6e-2 Task 3: koordinat-RPC'en (returkolonner med printed_page sidst, ACL) og den mængdebaserede afledning af
-- gældende medlemskab: private.membership_current_set() = {membership_is_current} over alle linjemedlemskaber.
DO $verify_6e2_koordinater$
DECLARE v_diff bigint; v_n bigint;
BEGIN
  IF (SELECT array_to_string(p.proargnames,',') FROM pg_proc p WHERE p.oid=to_regprocedure('public.public_person_source_coordinates()'))
     IS DISTINCT FROM 'person_id,source_id,legacy_line_code,printed_number,printed_number_label,generation_local,generation_global,kuld_label,provenance_kind,printed_page' THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6e-2 koordinat-RPC''ens returkolonner';
  END IF;
  IF NOT has_function_privilege('anon','public.public_person_source_coordinates()','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.public_person_source_coordinates()','EXECUTE')
     OR EXISTS (SELECT 1 FROM pg_proc p, aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x
                 WHERE p.oid='public.public_person_source_coordinates()'::regprocedure AND x.grantee=0) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6e-2 koordinat-RPC''ens ACL';
  END IF;
  IF to_regprocedure('private.membership_current_set()') IS NULL
     OR has_function_privilege('anon','private.membership_current_set()','EXECUTE')
     OR has_function_privilege('authenticated','private.membership_current_set()','EXECUTE')
     OR has_function_privilege('service_role','private.membership_current_set()','EXECUTE') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6e-2 membership_current_set mangler eller er åben for klienter';
  END IF;
  SELECT count(*) INTO v_diff FROM (
    (SELECT m.person_id,m.lineage_id FROM public.person_lineage_membership m
      WHERE private.membership_is_current(m.person_id,m.lineage_id) IS TRUE
     EXCEPT ALL SELECT s.person_id,s.lineage_id FROM private.membership_current_set() s)
    UNION ALL
    (SELECT s.person_id,s.lineage_id FROM private.membership_current_set() s
     EXCEPT ALL SELECT m.person_id,m.lineage_id FROM public.person_lineage_membership m
      WHERE private.membership_is_current(m.person_id,m.lineage_id) IS TRUE)) d;
  IF v_diff<>0 THEN
    RAISE EXCEPTION 'VERIFY_FAILED: 6e-2 membership_current_set afviger fra membership_is_current (% rækker)',v_diff;
  END IF;
  SELECT count(*) INTO v_n FROM private.membership_current_set();
  RAISE NOTICE 'OK: trin 6e-2 — koordinat-RPC og mængdebaseret medlemskab (% gældende, 0 forskelle)',v_n;
END $verify_6e2_koordinater$;

-- Kodereview 36 P6: FK'en conclusion.valgt_assertion_id har et indeks, hvis første kolonne er netop den.
DO $verify_p6_conclusion_index$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_index i
     WHERE i.indrelid='public.conclusion'::regclass AND i.indisvalid
       AND i.indkey[0]=(SELECT a.attnum FROM pg_attribute a
                         WHERE a.attrelid='public.conclusion'::regclass AND a.attname='valgt_assertion_id')) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: P6 conclusion.valgt_assertion_id mangler indeks';
  END IF;
  RAISE NOTICE 'OK: P6 — conclusion.valgt_assertion_id er indekseret';
END $verify_p6_conclusion_index$;

-- Kodereview 36 K6: højst ét primært portræt pr. person, håndhævet af en udskudt exclusion constraint, og ingen person
-- har i dag mere end ét flag.
DO $verify_k6_portraet$
DECLARE v_dup bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.relation'::regclass AND conname='relation_hoejst_et_primaert_portraet'
                    AND contype='x' AND condeferrable AND condeferred) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: K6 relation_hoejst_et_primaert_portraet mangler eller er ikke DEFERRABLE INITIALLY DEFERRED';
  END IF;
  SELECT count(*) INTO v_dup FROM (
    SELECT subjekt_id FROM public.relation
     WHERE subjekt_type='person' AND objekt_type='media' AND rolle='afbildet' AND kvalifikator ? 'primaer'
     GROUP BY subjekt_id HAVING count(*)>1) d;
  IF v_dup<>0 THEN
    RAISE EXCEPTION 'VERIFY_FAILED: K6 % personer har mere end ét primært portræt',v_dup;
  END IF;
  RAISE NOTICE 'OK: K6 — højst ét primært portræt pr. person (udskudt exclusion constraint)';
END $verify_k6_portraet$;

-- Kodereview 36 P2: public_person_source_coordinates_samlet() er de samme rækker som public_person_source_coordinates()
-- (samme felter og orden) som ét jsonb-array, for ejeren og for anon; samme sikkerhed og ACL som rækkefunktionen.
DO $verify_p2_koordinater_samlet$
DECLARE f regprocedure:=to_regprocedure('public.public_person_source_coordinates_samlet()'); i int; v_n bigint;
BEGIN
  IF f IS NULL OR NOT (SELECT prosecdef FROM pg_proc WHERE oid=f)
     OR (SELECT proconfig FROM pg_proc WHERE oid=f) IS DISTINCT FROM ARRAY['search_path=pg_catalog']
     OR pg_get_function_result(f)<>'jsonb'
     OR NOT has_function_privilege('anon',f,'EXECUTE') OR NOT has_function_privilege('authenticated',f,'EXECUTE')
     OR EXISTS (SELECT 1 FROM pg_proc p, aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x
                 WHERE p.oid=f AND x.grantee=0) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: P2 public_person_source_coordinates_samlet mangler eller har forkert sikkerhed/ACL';
  END IF;
  FOR i IN 1..2 LOOP
    IF i=2 THEN SET LOCAL ROLE anon; END IF;
    IF public.public_person_source_coordinates_samlet() IS DISTINCT FROM (
         SELECT coalesce(jsonb_agg(to_jsonb(o)-'ordinality' ORDER BY o.ordinality),'[]'::jsonb)
           FROM public.public_person_source_coordinates() WITH ORDINALITY o) THEN
      RESET ROLE;
      RAISE EXCEPTION 'VERIFY_FAILED: P2 den samlede koordinatfunktion afviger fra rækkefunktionen (%)',
        CASE i WHEN 1 THEN 'ejer' ELSE 'anon' END;
    END IF;
    RESET ROLE;
  END LOOP;
  SELECT jsonb_array_length(public.public_person_source_coordinates_samlet()) INTO v_n;
  RAISE NOTICE 'OK: P2 — koordinaterne i ét kald (% rækker, ens med rækkefunktionen for ejer og anon)',v_n;
END $verify_p2_koordinater_samlet$;

-- Fuld personsletning (2026-11-14), Task 8a: eksistensvagter, låsesikkerhed og privat udbakke.
DO $verify_person_purge_vagt$
DECLARE r record; f regprocedure; v_role text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('fact','trg_polymorf_fact','private.validate_polymorf_subjekt_findes()',23),
    ('note','trg_polymorf_note','private.validate_polymorf_subjekt_findes()',23),
    ('narrative','trg_polymorf_narrative','private.validate_polymorf_subjekt_findes()',23),
    ('story','trg_polymorf_story','private.validate_polymorf_subjekt_findes()',23),
    ('suggestion','trg_polymorf_suggestion','private.validate_polymorf_subjekt_findes()',23),
    ('relation','trg_polymorf_relation','private.validate_polymorf_subjekt_findes()',23),
    ('assertion','trg_assertion_0_polymorf_objekt','private.validate_polymorf_subjekt_findes()',23),
    ('haendelse','trg_polymorf_haendelse','private.validate_polymorf_subjekt_findes()',23),
    ('assertion','trg_assertion_relation_target','public.enforce_relation_evidence_target()',23),
    ('conclusion','trg_conclusion_relation_target','public.enforce_relation_evidence_target()',23),
    ('note','trg_note_relation_target','public.enforce_relation_evidence_target()',23),
    ('fact','trg_fact_evidence_delete','private.guard_fact_evidence_delete()',11),
    ('entity_description','trg_entity_description_subject','public.validate_entity_description_subject()',23),
    ('media','trg_media_person_purge_udbakke_genbrug','private.person_purge_udbakke_genbrug()',21),
    ('media_variant','trg_media_variant_person_purge_udbakke_genbrug','private.person_purge_udbakke_genbrug()',21)
  ) x(tabel,triggernavn,funktion,triggerart) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid=to_regclass('public.'||r.tabel)
      AND t.tgname=r.triggernavn AND t.tgfoid=to_regprocedure(r.funktion)
      AND t.tgtype=r.triggerart AND t.tgenabled IN ('O','A') AND NOT t.tgisinternal) THEN
      RAISE EXCEPTION 'VERIFY_FAILED: person_purge vagt mangler/disabled: %',r.triggernavn;
    END IF;
  END LOOP;
  FOR r IN SELECT * FROM (VALUES
    ('private.validate_polymorf_subjekt_findes()'),('private.guard_fact_evidence_delete()'),
    ('private.person_purge_udbakke_genbrug()'),
    ('private.feed_pin_maal(text)'),('private.laas_feed_pin_maal(text)'),('public.enforce_relation_evidence_target()'),
    ('public.validate_entity_description_subject()'),('public.red_set_feed_pin(text,text)'),
    ('public.red_fortryd_change_set(bigint,boolean)')
  ) x(funktion) LOOP
    f:=to_regprocedure(r.funktion);
    IF f IS NULL OR NOT (SELECT prosecdef FROM pg_proc WHERE oid=f)
       OR (SELECT proconfig FROM pg_proc WHERE oid=f) IS DISTINCT FROM
          (CASE WHEN r.funktion='public.red_fortryd_change_set(bigint,boolean)' THEN ARRAY['search_path=public']
               ELSE ARRAY['search_path=pg_catalog, public, private'] END) THEN
      RAISE EXCEPTION 'VERIFY_FAILED: person_purge vagt SECURITY DEFINER/search_path: %',r.funktion;
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      IF has_function_privilege(v_role,f,'EXECUTE') IS DISTINCT FROM
         (r.funktion IN ('public.red_set_feed_pin(text,text)','public.red_fortryd_change_set(bigint,boolean)')
          AND v_role='authenticated') THEN
        RAISE EXCEPTION 'VERIFY_FAILED: person_purge vagt ACL: % / %',r.funktion,v_role;
      END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM pg_proc p,aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
                WHERE p.oid=f AND a.grantee=0 AND a.privilege_type='EXECUTE') THEN
      RAISE EXCEPTION 'VERIFY_FAILED: person_purge vagt PUBLIC ACL: %',r.funktion;
    END IF;
  END LOOP;
  -- UPDATE OF skal dække hele sti-identiteten; ingen WHEN-betingelse må omgå genbrugsvagten.
  FOR r IN SELECT * FROM (VALUES
    ('media','trg_media_person_purge_udbakke_genbrug',ARRAY['bucket','storage_path']::text[]),
    ('media_variant','trg_media_variant_person_purge_udbakke_genbrug',ARRAY['storage_path']::text[])
  ) x(tabel,triggernavn,kolonner) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_trigger t
      WHERE t.tgrelid=to_regclass('public.'||r.tabel) AND t.tgname=r.triggernavn
        AND t.tgqual IS NULL AND NOT t.tgdeferrable AND t.tgnargs=0
        AND (SELECT array_agg(a.attname::text ORDER BY a.attname)
          FROM unnest(t.tgattr::smallint[]) n(attnum)
          JOIN pg_attribute a ON a.attrelid=t.tgrelid AND a.attnum=n.attnum)=r.kolonner) THEN
      RAISE EXCEPTION 'VERIFY_FAILED: person_purge udbakke genbrug triggerkolonner: %',r.triggernavn;
    END IF;
  END LOOP;
  -- Relationsvagtlisten omfatter begge media-ender; samme type-/låsekontrakt som fact.
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='private.validate_polymorf_subjekt_findes()'::regprocedure
    AND position('FROM public.media WHERE id=r.id FOR KEY SHARE' IN prosrc)>0
    AND position('IN (''fact'',''media'')' IN prosrc)>0
    AND position('WHEN ''fact'' THEN 3 ELSE 4 END' IN prosrc)>0
    AND position('POLYMORF_TYPE_IKKE_KANONISK' IN prosrc)>0) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: person_purge vagt media-ender/type/låseorden';
  END IF;
  IF to_regclass('private.person_purge_udbakke') IS NULL
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private.person_purge_udbakke'::regclass)
     OR NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid='private.person_purge_udbakke'::regclass
         AND c.contype='p' AND pg_get_constraintdef(c.oid)='PRIMARY KEY (bucket, sti)') THEN
    RAISE EXCEPTION 'VERIFY_FAILED: person_purge_udbakke mangler/RLS/PK';
  END IF;
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_table_privilege(v_role,'private.person_purge_udbakke','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
      RAISE EXCEPTION 'VERIFY_FAILED: person_purge_udbakke klientadgang: %',v_role;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_class c,aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
              WHERE c.oid='private.person_purge_udbakke'::regclass AND a.grantee=0) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: person_purge_udbakke PUBLIC ACL';
  END IF;
  RAISE NOTICE 'OK: person_purge Task 8a — enabled vagter, DEFINER/search_path/ACL og privat udbakke';
END $verify_person_purge_vagt$;

-- Fuld personsletning (2026-11-14), Task 8b: eksakt RPC-kontrakt og ACL (R34).
DO $purge_execute_catalog$
DECLARE v_oid oid:=to_regprocedure('public.red_slet_person_helt(bigint,text)'); v_role text;
BEGIN
  IF v_oid IS NULL OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid=v_oid
    AND prosecdef AND prorettype='jsonb'::regtype AND NOT proretset
    AND proconfig @> ARRAY['search_path=pg_catalog, public, private']) THEN
    RAISE EXCEPTION 'PURGE_EXECUTE_CATALOG_DRIFT';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    WHERE p.oid=v_oid AND a.grantee=0 AND a.privilege_type='EXECUTE')
    OR NOT has_function_privilege('authenticated',v_oid,'EXECUTE') THEN
    RAISE EXCEPTION 'PURGE_EXECUTE_ACL_DRIFT';
  END IF;
  FOREACH v_role IN ARRAY ARRAY['anon','service_role'] LOOP
    IF has_function_privilege(v_role,v_oid,'EXECUTE') THEN RAISE EXCEPTION 'PURGE_EXECUTE_ACL_DRIFT'; END IF;
  END LOOP;
END
$purge_execute_catalog$;

-- Fuld personsletning (2026-11-14), Task 10. Rene læse-/katalogkontroller, også i prod-ceremonien.
-- Markørerne afgrænser præcis de samme DO-blokke til harnessens positive og negative prøver.
-- BEGIN PERSON PURGE TASK 10 CHECKS
DO $purge_verify_manifest_empty$
DECLARE v_n bigint;
BEGIN
  SELECT count(*) INTO v_n FROM private.person_purge_manifest;
  IF v_n<>0 THEN RAISE EXCEPTION 'PURGE_MANIFEST_IKKE_TOMT: %',v_n; END IF;
END $purge_verify_manifest_empty$;

DO $purge_verify_book_tables$
DECLARE v_tabel text;
BEGIN
  -- Uafhængig liste fra Global Constraints/slettegraf §3.2 (R27), IKKE en scanning af skriverkroppe.
  SELECT t.tabel INTO v_tabel FROM private.person_purge_tilladte_tabeller() t
  WHERE t.tabel IN (
    'private.source_record','private.source_occurrence','private.source_record_occurrence',
    'private.source_record_anchor_event','private.source_record_placement','private.source_record_placement_decision',
    'private.source_record_revision_event','private.source_observation','private.source_observation_text',
    'private.source_mention','private.source_rendition','private.extraction_run',
    'private.source_persona','private.source_persona_mention','private.source_persona_placement',
    'private.source_persona_placement_decision','private.interpretation','private.interpretation_observation',
    'private.interpretation_party','private.identity_control_run','private.identity_control_sample',
    'private.identity_control_event','private.identity_control_exclusion','private.reimport_writer_profile',
    'private.narrative_record_cutover_receipt','private.clause_disposition')
    OR t.tabel LIKE 'private.source\_record\_%' OR t.tabel LIKE 'private.source\_observation\_%'
    OR t.tabel LIKE 'private.source\_persona\_placement%'
  ORDER BY t.tabel COLLATE "C" LIMIT 1;
  IF FOUND THEN RAISE EXCEPTION 'PURGE_TILLADELSESLISTE_BOGTABEL: %',v_tabel; END IF;
END $purge_verify_book_tables$;

DO $purge_verify_polymorf$
DECLARE r record; v_type text; v_n bigint; v_bad_type bigint;
BEGIN
  -- Note 72 på familie 54 findes i prod og slettes i Task 13 FØR db-verify.
  -- Ingen undtagelse her. Ingen rækkeindhold/id i fejlen, kun tabelnavn og antal.
  -- Person/family på eksistensvagtens kolonnepar; fact/relation på evidensmål og relationsender;
  -- media på begge relationsender (8b runde 2) samt beskrivelser/noter med mediemål.
  -- Lower bruges KUN til at opdage ikke-kanoniske typer; opslaget kræver derefter kanonisk type.
  FOR r IN SELECT * FROM (VALUES
    ('fact','subjekt_type','subjekt_id',ARRAY['person','family']),
    ('note','target_type','target_id',ARRAY['person','family','fact','relation','media']),
    ('narrative','subjekt_type','subjekt_id',ARRAY['person','family']),
    ('story','subjekt_type','subjekt_id',ARRAY['person','family']),
    ('suggestion','subjekt_type','subjekt_id',ARRAY['person','family']),
    ('relation','subjekt_type','subjekt_id',ARRAY['person','family','fact','relation','media']),
    ('relation','objekt_type','objekt_id',ARRAY['person','family','fact','relation','media']),
    ('assertion','objekt_type','objekt_id',ARRAY['person','family']),
    ('assertion','target_type','target_id',ARRAY['fact','relation']),
    ('conclusion','target_type','target_id',ARRAY['fact','relation']),
    ('haendelse','subjekt_type','subjekt_id',ARRAY['person','family']),
    ('entity_description','subjekt_type','subjekt_id',ARRAY['person','family','media'])
  ) x(tabel,typekolonne,idkolonne,typer) LOOP
    EXECUTE format('SELECT count(*) FROM public.%I WHERE lower(%I)=ANY($1) AND %I<>lower(%I)',
      r.tabel,r.typekolonne,r.typekolonne,r.typekolonne) INTO v_bad_type USING r.typer;
    IF v_bad_type<>0 THEN
      RAISE EXCEPTION 'POLYMORF_TYPE_IKKE_KANONISK: % %',r.tabel,v_bad_type;
    END IF;
    FOREACH v_type IN ARRAY r.typer LOOP
      EXECUTE format('SELECT count(*) FROM public.%I t WHERE t.%I=$1 AND t.%I IS NOT NULL
        AND NOT EXISTS(SELECT 1 FROM public.%I p WHERE p.id=t.%I)',
        r.tabel,r.typekolonne,r.idkolonne,v_type,r.idkolonne) INTO v_n USING v_type;
      IF v_n<>0 THEN RAISE EXCEPTION 'POLYMORF_SUBJEKT_FORAELDRELOES: % %',r.tabel,v_n; END IF;
    END LOOP;
  END LOOP;
END $purge_verify_polymorf$;

DO $purge_verify_manifest_writer$
DECLARE v_writers oid[]; v_names text;
BEGIN
  -- Alle funktioner/procedurer i kataloget, også uden for public/private. Udelad kun kommentarer.
  -- Medtag også citerede navne, ONLY og ukvalificeret INSERT (search_path kan være private).
  SELECT array_agg(p.oid ORDER BY p.oid),string_agg(p.oid::regprocedure::text,', ' ORDER BY p.oid)
    INTO v_writers,v_names FROM pg_proc p WHERE p.prokind IN ('f','p')
    AND regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','gs'),'--[^\n]*',' ','g')
      ~* '\minsert\s+into\s+(only\s+)?("?private"?\s*\.\s*)?"?person_purge_manifest"?\M';
  IF v_writers IS DISTINCT FROM ARRAY[to_regprocedure('public.red_slet_person_helt(bigint,text)')::oid] THEN
    RAISE EXCEPTION 'PURGE_MANIFEST_SKRIVER: %',coalesce(v_names,'red_slet_person_helt');
  END IF;
END $purge_verify_manifest_writer$;

DO $purge_verify_inventory_hash$
DECLARE v_hash text;
BEGIN
  -- Hashkontrakt: én jsonb-array [sted,tabel,kolonner,handling,fase,grund] pr. række,
  -- sorteret som UTF-8-tekst med COLLATE "C", samlet med LF, uden afsluttende LF.
  -- Arrays bevarer kolonneordenen; NULL/dubletter bevares. Ingen ICU/libc-sorteringsforskel.
  -- Ved bevidst inventarændring: gennemse diffen i slettegraf/inventar og kør SELECT'en nedenfor
  -- i en engangsbase med det nye schema. Erstat først derefter konstanten med det beregnede md5.
  SELECT md5(coalesce(string_agg(j,E'\n' ORDER BY j COLLATE "C"),'')) INTO v_hash FROM (
    SELECT jsonb_build_array(i.sted,i.tabel,i.kolonner,i.handling,i.fase,i.grund)::text j
      FROM private.person_purge_inventar() i) s;
  -- visning-floruit (2026-11-19): S1 fik person.visning_floruit (ny afledt cachekolonne på P's egen række).
  -- Review 37 P1+P2 (2026-11-20): NY-E (media, skjul) — bevaret medie med ikke-offentlig P afbildet låses.
  IF v_hash IS DISTINCT FROM '60997b375d304d00bc528dcd84c66b82' THEN
    RAISE EXCEPTION 'PURGE_INVENTAR_HASH: person_purge_inventar';
  END IF;
END $purge_verify_inventory_hash$;

-- Flyttet samlet fra C3-katalogblokken ovenfor, så harnessen prøver den eksisterende vagt direkte.
DO $purge_verify_identity_writers$
DECLARE v_writer regprocedure; v_definition text; v_lock_position int; v_people_position int;
BEGIN
  FOREACH v_writer IN ARRAY ARRAY[
    'public.red_samme_som(bigint,bigint)'::regprocedure,
    'public.red_ikke_samme_som(bigint,bigint)'::regprocedure,
    'public.red_slet_person(bigint)'::regprocedure,
    'public.red_slet_person_helt(bigint,text)'::regprocedure
  ] LOOP
    v_definition := pg_get_functiondef(v_writer);
    v_lock_position := strpos(v_definition, 'pg_advisory_xact_lock(hashtext(''samme_som_mutation''))');
    v_people_position := strpos(v_definition, 'private.lock_identity_people');
    IF v_lock_position < 1 OR v_people_position <= v_lock_position THEN
      RAISE EXCEPTION 'IDENTITY_WRITER_LOCK_ORDER_DRIFT: %', v_writer;
    END IF;
  END LOOP;
END $purge_verify_identity_writers$;

DO $purge_verify_lock_order$
DECLARE v_body text; r record; v_position int; v_previous int:=0;
BEGIN
  SELECT regexp_replace(regexp_replace(prosrc,'/\*.*?\*/',' ','gs'),'--[^\n]*',' ','g') INTO v_body
    FROM pg_proc WHERE oid=to_regprocedure('public.red_slet_person_helt(bigint,text)');
  -- Faktiske sætninger, ALDRIG L-kommentarernes position. Kræv præcis ét match pr. trin
  -- OG strengt stigende positioner: at bytte to sætninger beholder alle navne, men fejler stadig.
  -- L2's rollegate er udført før L1; L3-L13 er derefter den besluttede låse-/valideringsorden.
  FOR r IN SELECT pattern FROM (VALUES
    (1,$re$PERFORM pg_advisory_xact_lock_shared\(hashtextextended\('daa-narrative-record-contract',0\)\);$re$),
    (3,$re$v_laas\s*:=\s*private.person_purge_laasemaengder\(p_person_id\);$re$),
    (4,$re$PERFORM private.lock_reimport_writer\(v_prof.source_id,v_prof.profile_id\);$re$),
    (5,$re$PERFORM pg_advisory_xact_lock\(hashtextextended\('daa-identity-candidates:'\|\|v_source::text,0\)\);$re$),
    (6,$re$PERFORM 1 FROM private.source_record WHERE[^;]*ORDER BY id FOR UPDATE;$re$),
    (7,$re$PERFORM 1 FROM private.source_persona WHERE[^;]*ORDER BY id FOR UPDATE;$re$),
    (8,$re$PERFORM 1 FROM private.source_persona_identity WHERE[^;]*ORDER BY source_persona_id FOR UPDATE;$re$),
    (9,$re$PERFORM 1 FROM public.change_set WHERE id=ANY\(v_saet\) ORDER BY id FOR UPDATE;$re$),
    (10,$re$PERFORM pg_advisory_xact_lock\(hashtext\('samme_som_mutation'\)\);$re$),
    (11,$re$PERFORM private.guard_identity_mutation_snapshot\(\);$re$),
    (12,$re$LOCK TABLE public.change_set IN ROW EXCLUSIVE MODE;$re$),
    (13,$re$PERFORM 1 FROM public.source s JOIN public.person_external_id pei[^;]*FOR UPDATE OF s,pei;$re$),
    (14,$re$PERFORM private.lock_identity_people\(v_people\);$re$),
    (15,$re$PERFORM private.lock_family_rows\(ARRAY\[p_person_id\]\);$re$),
    (16,$re$PERFORM 1 FROM public.media WHERE id=ANY\(v_medier\) ORDER BY id FOR UPDATE;$re$),
    (17,$re$v_nu\s*:=\s*private.person_purge_laasemaengder\(p_person_id\);$re$),
    (18,$re$v_preview\s*:=\s*private.person_purge_preview_fra_plan\(p_person_id,v_plan\);$re$)
  ) x(n,pattern) ORDER BY n LOOP
    v_position:=regexp_instr(v_body,r.pattern,1,1,0,'i');
    IF v_position IS NULL OR v_position<=v_previous OR regexp_count(v_body,r.pattern,1,'i')<>1 THEN
      RAISE EXCEPTION 'PURGE_LOCK_ORDER: red_slet_person_helt';
    END IF;
    v_previous:=v_position;
  END LOOP;
END $purge_verify_lock_order$;

DO $purge_verify_allocators$
DECLARE
  r record; v_col text; v_body text; v_first int;
  -- Døde v1-veje (navngiven liste). Kun narrative-id-grenen i denne ene helper er tilbage;
  -- red_fortryd_change_set bruger sekvensen og har ingen max+1-undtagelse (Task 9).
  v_dead_v1 regprocedure[]:=ARRAY[
    'private.write_reimport_case_narrative(bigint,bigint,bigint,text,boolean,text)'::regprocedure
  ];
BEGIN
  -- Alle katalogfunktioner/procedurer; ingen afgrænsning til RPC-navne, volatilitet eller skema.
  -- Scan også ordinaler. Hver undtagelse er et (signatur,kolonnenavn)-par, aldrig et helt funktionsfripas.
  FOR r IN SELECT p.oid,p.prosrc FROM pg_proc p WHERE p.prokind IN ('f','p') ORDER BY p.oid LOOP
    v_body:=regexp_replace(regexp_replace(r.prosrc,'/\*.*?\*/',' ','gs'),'--[^\n]*',' ','g');
    FOR v_col IN SELECT lower(regexp_replace(m[1],'["[:space:]]','','g')) FROM regexp_matches(v_body,
      $re$\mmax\s*\(\s*((?:"?[a-z_][a-z_0-9]*"?\s*\.\s*)?"?[a-z_][a-z_0-9]*"?)\s*\)\s*(?:,\s*0\s*\))?\s*\+\s*1\M$re$,'gi') m LOOP
      v_col:=regexp_replace(v_col,'^.*\.','');
      -- Navngiven død v1-vej: kun narrative-id-grenen, og kun mens kontrakt >=2 afviser FØR max-læsningen.
      IF r.oid::regprocedure=ANY(v_dead_v1)
         AND v_col='id' AND public.narrative_record_contract_version()>=2 THEN
        v_first:=regexp_instr(v_body,'\mmax\s*\(',1,1,0,'i');
        IF strpos(v_body,'IF public.narrative_record_contract_version()>=2 THEN RAISE EXCEPTION ''NARRATIVE_RECORD_LEGACY_WRITER_DISABLED''; END IF;')
             BETWEEN 1 AND v_first-1 THEN CONTINUE; END IF;
      END IF;
      -- Versionsordinaler, ikke entitets-id'er. Append-only strømme bevarer deres numre ved purge.
      -- Især reverse_narrative_publication_event: max(stream_version)+1 er næste position i SAMME
      -- stream_ref, mens event-id kommer fra uuid-default. Den aktive vej må derfor ikke kaldes en død v1-vej.
      IF EXISTS (SELECT 1 FROM (VALUES
        ('private.validate_clause_disposition()','version'),
        ('private.validate_source_record_anchor_event()','version'),
        ('private.validate_source_record_revision_event()','version'),
        ('private.add_interpretation_promotion_rule_version(text,text,text,text,text,text,boolean,boolean,boolean,text,text)','rule_version'),
        ('private.validate_source_persona_identity_event()','version'),
        ('private.migrate_legacy_narrative_record(uuid,text,jsonb)','stream_version'),
        ('private.write_clause_revision(uuid,text,jsonb)','version'),
        ('private.write_source_text_revision(uuid,text,jsonb)','version'),
        ('private.mutate_person_narrative_record(text,bigint,bigint,text,text,boolean,text)','stream_version'),
        ('private.withdraw_legacy_narrative(uuid,text,text)','stream_version'),
        ('private.reverse_narrative_publication_event(uuid,text)','stream_version'),
        ('private.write_relation_persona(uuid,text,jsonb)','version'),
        ('public.red_afgoer_relation_interpretation(uuid,integer,text,bigint,text,jsonb)','version'),
        ('private.append_control_event(uuid,text,text,text,text)','seq'),
        ('private.append_parent_card_event(uuid,text,text,jsonb)','seq'),
        ('private.append_relation_classification(uuid,text,jsonb)','seq')
      ) x(funktion,kolonne) WHERE r.oid=to_regprocedure(x.funktion) AND v_col=x.kolonne) THEN CONTINUE; END IF;
      RAISE EXCEPTION 'ID_MAX_PLUS_ONE_ALLOCATOR: %',r.oid::regprocedure;
    END LOOP;
  END LOOP;
  -- Cutoverens ALTER SEQUENCE RESTART flytter sekvensgulvet transaktionelt og monotont under tabellås;
  -- den allokerer rækker via DEFAULT. max(id) -> sekvensgulv er ikke en max+1-id-allokator.
END $purge_verify_allocators$;
-- END PERSON PURGE TASK 10 CHECKS

-- ===== #415: synlighed pr. samme_som-gruppe =====
-- Ingen fixtures, ingen skrivning: kan køres i prod-transaktionen. Adfærden testes i tests/sql/test-person-offentlig-gruppe.sql.
-- Forvent: NOTICE "OK: #415 synlighed pr. samme_som-gruppe".
DO $verify_415_gruppe$
DECLARE f regprocedure; v_tg text; v_laek bigint;
BEGIN
  f:=to_regprocedure('public.person_gruppe_skjult(bigint)');
  IF f IS NULL OR NOT (SELECT prosecdef FROM pg_proc WHERE oid=f)
     OR (SELECT proconfig FROM pg_proc WHERE oid=f) IS DISTINCT FROM ARRAY['search_path=pg_catalog, public']
     OR (SELECT proacl FROM pg_proc WHERE oid=f) IS NULL
     OR EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid=f AND a.grantee=0)
     OR has_function_privilege('anon',f,'EXECUTE') OR has_function_privilege('authenticated',f,'EXECUTE')
     OR (EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') AND has_function_privilege('service_role',f,'EXECUTE')) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: #415: person_gruppe_skjult mangler, er ikke DEFINER med fast search_path eller er kaldbar af en klientrolle';
  END IF;
  -- staged må ikke smitte (decisions 2026-11-21); levende/privat skal.
  IF strpos(pg_get_functiondef(f),'staged')>0
     OR strpos(pg_get_functiondef(f),'m.levende IS FALSE AND NOT coalesce(m.privat,false)')=0
     OR (SELECT l.lanname FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=f)<>'plpgsql' THEN
    RAISE EXCEPTION 'VERIFY_FAILED: #415: person_gruppe_skjult har ikke reglen levende/privat smitter, staged ikke';
  END IF;
  IF strpos(pg_get_functiondef('public.person_offentlig(bigint)'::regprocedure),'and not public.person_gruppe_skjult(pid)')=0 THEN
    RAISE EXCEPTION 'VERIFY_FAILED: #415: person_offentlig kalder ikke person_gruppe_skjult';
  END IF;
  IF strpos(pg_get_functiondef('public.regen_person_floruit(bigint)'::regprocedure),'public.person_gruppe_skjult(q.id)')=0
     OR strpos(pg_get_functiondef('public.trg_regen_from_person_offentlighed()'::regprocedure),'_samme_som_gruppe(NEW.id)')=0 THEN
    RAISE EXCEPTION 'VERIFY_FAILED: #415: floruit-cachen kender ikke samme_som-gruppen';
  END IF;
  -- Delindekserne bag hjælperens opslag (ydelse; anon-loftet er 3 s).
  IF to_regclass('public.ix_relation_samme_som_subjekt') IS NULL OR to_regclass('public.ix_relation_samme_som_objekt') IS NULL THEN
    RAISE EXCEPTION 'VERIFY_FAILED: #415: delindekserne på samme_som-kanterne mangler';
  END IF;
  FOREACH v_tg IN ARRAY ARRAY['trg_samme_som_regen_ins','trg_samme_som_regen_del'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid='public.relation'::regclass AND t.tgname=v_tg
                    AND t.tgenabled='O' AND t.tgqual IS NOT NULL
                    AND t.tgfoid='public.trg_regen_from_samme_som()'::regprocedure::oid) THEN
      RAISE EXCEPTION 'VERIFY_FAILED: #415: relation-triggeren % mangler', v_tg;
    END IF;
  END LOOP;
  -- Data: ingen offentlig person-række har et samme_som-gruppemedlem, der er levende/ukendt/privat.
  WITH RECURSIVE e AS (
    SELECT subjekt_id a, objekt_id b FROM public.relation
     WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
  ), u AS (SELECT a,b FROM e UNION SELECT b,a FROM e),
  reach(start,pid) AS (SELECT a,a FROM u UNION SELECT reach.start,u.b FROM reach JOIN u ON u.a=reach.pid)
  SELECT count(DISTINCT r.start) INTO v_laek
    FROM reach r LEFT JOIN public.person m ON m.id=r.pid
   WHERE r.start<>r.pid AND public.person_offentlig(r.start)
     AND (m.id IS NULL OR m.levende IS NOT FALSE OR coalesce(m.privat,false));
  IF v_laek<>0 THEN
    RAISE EXCEPTION 'VERIFY_FAILED: #415: % offentlige personer har et levende/privat samme_som-gruppemedlem', v_laek;
  END IF;
  RAISE NOTICE 'OK: #415 synlighed pr. samme_som-gruppe';
END $verify_415_gruppe$;

-- Review 37 Y1 (#397): red_person_grid_udsnit skal tvinge custom plan. Uden indstillingen skifter plpgsql efter 5 kald
-- til en generisk plan til små arrays, og et vindue à 500 tog 22 s i stedet for 0,3 s på en prod-kopi. En senere
-- CREATE OR REPLACE uden SET-klausulen ville fjerne den lydløst; de syntetiske tests er for små til at mærke det.
DO $verify_review37_y1$
DECLARE f regprocedure := to_regprocedure('public.red_person_grid_udsnit(bigint,integer,bigint)');
BEGIN
  IF f IS NULL THEN RAISE EXCEPTION 'VERIFY_FAILED: review 37 Y1: red_person_grid_udsnit mangler'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=f AND p.prosecdef
                  AND p.proconfig @> ARRAY['search_path=public, pg_temp','plan_cache_mode=force_custom_plan']::text[]) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: review 37 Y1: red_person_grid_udsnit skal være SECURITY DEFINER med search_path og plan_cache_mode=force_custom_plan';
  END IF;
  RAISE NOTICE 'OK: review 37 Y1 red_person_grid_udsnit tvinger custom plan';
END $verify_review37_y1$;

-- BEGIN-VERIFY c1
-- ===== Review 37 ceremoni 1 (#397: Y8, Y10, S6, S9) =====
-- S9: den præcise mængde af public-funktioner uden for red_* (ikke-extension), som anon og authenticated må kalde.
-- red_* har sin egen vagt ovenfor. Listen er bevidst skrevet uafhængigt af db-rls.sql og målt i prod 2026-11-24:
-- gæste-API'er (public_*, narrative_record_contract_version), RLS-hjælpere (*_offentlig, media_*_synlig_anon,
-- person_daa_narrative_publication_allowed), beregnede felter/visninger (side_trykt, source_trykt_side, lineage_*,
-- slaegtsnavn_*) og for authenticated desuden current_rolle og historikkens hist_*. Triggere og interne skrivere er
-- fjernet med $review37_c1_execute$. EN NY KLIENTKALDBAR FUNKTION skal føjes hertil (anon: også docs/decisions.md).
DO $$
DECLARE v_fejl text; v_state text; v_uid uuid := '00000000-0000-0000-0000-0000000c1c1c';
BEGIN
  WITH begge(fn) AS (VALUES
    ('entitet_offentlig(text, bigint)'), ('lineage_ancestors(bigint)'), ('lineage_descendants(bigint)'),
    ('lineage_effective_slaegtsnavn(bigint)'), ('media_object_synlig_anon(text)'), ('media_synlig_anon(bigint)'),
    ('narrative_record_contract_version()'), ('person_daa_narrative_publication_allowed(bigint)'),
    ('person_offentlig(bigint)'), ('public_family_sources(bigint[])'), ('public_haendelse_feed(text, integer, integer)'),
    ('public_person_bio_source_versions(bigint[])'), ('public_person_bio_source_versions_v2(bigint[])'),
    ('public_person_facts(bigint[])'), ('public_person_source_coordinates()'),
    ('public_person_source_coordinates_samlet()'), ('side_trykt(citation)'), ('slaegtsnavn_normaliser(text)'),
    ('slaegtsnavn_suffiks_match(text, text)'), ('source_trykt_side(bigint, text)')),
  forventet(l) AS (
    SELECT r||':'||fn FROM begge, (VALUES ('anon'), ('authenticated')) v(r)
    UNION ALL SELECT 'authenticated:'||fn FROM (VALUES ('current_rolle()'), ('hist_events(bigint)'),
      ('hist_for_subjekt(text, bigint)'), ('hist_for_subjekter(text, bigint[])')) a(fn)),
  faktisk(l) AS (
    SELECT r.rolname||':'||p.proname||'('||oidvectortypes(p.proargtypes)||')'
      FROM pg_proc p CROSS JOIN (VALUES ('anon'), ('authenticated')) r(rolname)
     WHERE p.pronamespace = 'public'::regnamespace AND p.proname NOT LIKE 'red\_%' ESCAPE '\'
       AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')
       AND has_function_privilege(r.rolname, p.oid, 'EXECUTE'))
  SELECT coalesce(string_agg(CASE WHEN f.l IS NULL THEN ' mangler:'||e.l ELSE ' uventet:'||f.l END, ''
                             ORDER BY coalesce(e.l, f.l)), '')
    INTO v_fejl
    FROM forventet e FULL JOIN faktisk f ON e.l = f.l WHERE e.l IS NULL OR f.l IS NULL;
  IF v_fejl <> '' THEN
    RAISE EXCEPTION 'FEJL: review37 c1 S9 —%', v_fejl
      USING HINT = 'uventet = en public-funktion uden for red_*, som anon/authenticated kan kalde, men som ikke står på '
        || 'listen. Skal klienten kalde den: føj den til listen i db-verify.sql (enhed c1); for anon også en linje i '
        || 'docs/decisions.md. Ellers: REVOKE EXECUTE ON FUNCTION … FROM PUBLIC, anon, authenticated (ved navn; Supabase '
        || 'giver EXECUTE direkte). mangler = en funktion på listen er omdøbt/fjernet eller har mistet kalderetten.';
  END IF;

  -- Standardrettigheden: en ny funktion i public, som postgres opretter, giver ikke anon/authenticated/PUBLIC EXECUTE.
  SELECT string_agg(CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE x.grantee::regrole::text END, ', ') INTO v_state
    FROM pg_default_acl d, aclexplode(d.defaclacl) x
   WHERE d.defaclrole = to_regrole('postgres') AND d.defaclnamespace = 'public'::regnamespace AND d.defaclobjtype = 'f'
     AND x.privilege_type = 'EXECUTE' AND x.grantee IN (0, 'anon'::regrole, 'authenticated'::regrole);
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: review37 c1 S9 — nye public-funktioner får EXECUTE af sig selv (standardrettighed for postgres): %', v_state;
  END IF;

  -- Y8 + Y10: indeksene findes.
  IF to_regclass('private.ix_interpretation_promotion_target') IS NULL OR to_regclass('public.ix_fact_type_subjekt') IS NULL
     OR to_regclass('public.ix_fact_sted') IS NULL THEN
    RAISE EXCEPTION 'FEJL: review37 c1 Y8/Y10 — et indeks mangler';
  END IF;

  -- S6: red_suggest som en almindelig indlogget bruger (ikke redaktion).
  INSERT INTO auth.users(id, email) VALUES (v_uid, 'c1-forslag@test.invalid') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub', v_uid::text, true);
  BEGIN
    PERFORM red_suggest('fakta', 'source', NULL, 'titel', repeat('x', 40001));
    v_state := 'ingen fejl';
  EXCEPTION WHEN invalid_parameter_value THEN v_state := SQLERRM; END;
  IF v_state <> 'FORSLAG_FOR_STORT' THEN RAISE EXCEPTION 'FEJL: review37 c1 S6 — for stor værdi blev ikke afvist (%)', v_state; END IF;
  BEGIN
    PERFORM red_suggest('fakta', 'source', NULL, 'titel', 'x', NULL, jsonb_build_object('t', repeat('y', 65536)));
    v_state := 'ingen fejl';
  EXCEPTION WHEN invalid_parameter_value THEN v_state := SQLERRM; END;
  IF v_state <> 'FORSLAG_FOR_STORT' THEN RAISE EXCEPTION 'FEJL: review37 c1 S6 — for stor payload blev ikke afvist (%)', v_state; END IF;
  BEGIN
    PERFORM red_suggest('fakta', 'ikke_en_tabel', NULL, 'titel', 'x');
    v_state := 'ingen fejl';
  EXCEPTION WHEN invalid_parameter_value THEN v_state := SQLERRM; END;
  IF v_state <> 'FORSLAG_UKENDT_SUBJEKTTYPE' THEN RAISE EXCEPTION 'FEJL: review37 c1 S6 — ukendt subjekttype blev ikke afvist (%)', v_state; END IF;
  -- Grænsen selv, en tabel og et klientkaldenavn går igennem (også med store bogstaver).
  PERFORM red_suggest('fakta', 'Source', NULL, 'tekst', repeat('æ', 20000), repeat('k', 4000), '{}'::jsonb);
  PERFORM red_suggest('fakta', 'slaegt', NULL, 'titel', 'x');
  PERFORM set_config('request.jwt.claim.sub', '', true);
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM = 'ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: review37 c1 — klientkaldbare public-funktioner = listen; indeks Y8/Y10; red_suggest-lofter';
  ELSE RAISE; END IF;
END $$;
-- END-VERIFY c1

-- BEGIN-VERIFY media-slags
-- ===== Billedtype som kontrolleret ordliste (spec docs/superpowers/specs/2026-11-25-media-slags-ordliste-design.md) =====
-- Ordlisten er låst til en fast liste, som også står i MEDIA_SLAGS (packages/core/src/mediaVisning.ts; en core-test
-- låser den side). Et nyt motiv kræver en vocab-række, en linje i MEDIA_SLAGS og en linje her.
-- Skriver kun i en transaktion, der rulles tilbage. Forvent: NOTICE "OK: media-slags …".
DO $verify_media_slags$
DECLARE v_fejl text; v_id bigint; v_cs bigint; v_state text; v_msg text; v_slags text; v_antal bigint;
  f regprocedure := to_regprocedure('private.validate_media_slags()');
BEGIN
  -- (1) Præcis de seks koder med deres labels.
  WITH forventet(code, label) AS (VALUES
    ('portræt','Portræt'), ('våben','Våben'), ('segl','Segl'), ('medalje','Medalje'), ('gods','Gods'),
    ('dokument','Dokument')),
  faktisk AS (SELECT v.code, v.label FROM public.vocab v WHERE v.scheme = 'media_slags')
  SELECT coalesce(string_agg(CASE WHEN f2.code IS NULL THEN ' mangler:'||e.code||'='||e.label
                                  ELSE ' uventet:'||f2.code||'='||coalesce(f2.label,'NULL') END, ''
                             ORDER BY coalesce(e.code, f2.code)), '')
    INTO v_fejl
    FROM forventet e FULL JOIN faktisk f2 ON e.code = f2.code AND e.label IS NOT DISTINCT FROM f2.label
   WHERE e.code IS NULL OR f2.code IS NULL;
  IF v_fejl <> '' THEN RAISE EXCEPTION 'VERIFY_FAILED: media-slags — vocab media_slags ≠ den faste liste:%', v_fejl; END IF;

  -- (2) Triggeren: BEFORE INSERT OR UPDATE OF slags, pr. række, aktiv, på den rigtige funktion. Funktionen er
  -- SECURITY DEFINER med fast search_path og kan ikke kaldes af klientrollerne.
  IF f IS NULL OR NOT EXISTS (
       SELECT 1 FROM pg_trigger t
        WHERE t.tgrelid = 'public.media'::regclass AND t.tgname = 'trg_media_slags' AND NOT t.tgisinternal
          AND t.tgenabled = 'O' AND t.tgfoid = f::oid
          AND t.tgtype = (1 | 2 | 4 | 16)   -- ROW | BEFORE | INSERT | UPDATE (ikke DELETE/TRUNCATE)
          AND t.tgattr::text = (SELECT a.attnum::text FROM pg_attribute a   -- int2vector: kun kolonnen slags
                                 WHERE a.attrelid = 'public.media'::regclass AND a.attname = 'slags')
          AND t.tgqual IS NULL) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: media-slags — trg_media_slags mangler eller er ikke BEFORE INSERT OR UPDATE OF slags ON media FOR EACH ROW → private.validate_media_slags()';
  END IF;
  IF NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = f)
     OR (SELECT p.proconfig FROM pg_proc p WHERE p.oid = f) IS DISTINCT FROM ARRAY['search_path=pg_catalog, public, private']
     OR EXISTS (SELECT 1 FROM pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                 WHERE p.oid = f AND a.grantee = 0)
     OR has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE')
     OR (EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') AND has_function_privilege('service_role', f, 'EXECUTE')) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: media-slags — validate_media_slags er ikke DEFINER med fast search_path eller kan kaldes af en klientrolle';
  END IF;

  -- (3) Data: ingen række uden for ordlisten (i prod: dataflytningen er kørt, og triggeren holder den sådan).
  SELECT count(*) INTO v_antal FROM public.media m
   WHERE m.slags IS NULL OR m.slags NOT IN (SELECT v.code FROM public.vocab v WHERE v.scheme = 'media_slags');
  IF v_antal <> 0 THEN RAISE EXCEPTION 'VERIFY_FAILED: media-slags — % media-rækker har en billedtype uden for ordlisten', v_antal; END IF;

  -- (4) Adfærd. Gamle værdier oversættes (efter btrim), både ved INSERT og UPDATE.
  PERFORM set_config('app.change_set_id', '', true);
  INSERT INTO public.media(slags, titel) VALUES (' maleri ', '__verify_media_slags__') RETURNING id, slags INTO v_id, v_slags;
  IF v_slags IS DISTINCT FROM 'portræt' THEN RAISE EXCEPTION 'VERIFY_FAILED: media-slags — »maleri« blev til »%«, ikke portræt', v_slags; END IF;
  UPDATE public.media SET slags = 'scanning' WHERE id = v_id RETURNING slags INTO v_slags;
  IF v_slags IS DISTINCT FROM 'våben' THEN RAISE EXCEPTION 'VERIFY_FAILED: media-slags — »scanning« blev til »%«, ikke våben', v_slags; END IF;
  UPDATE public.media SET slags = 'foto' WHERE id = v_id RETURNING slags INTO v_slags;
  IF v_slags IS DISTINCT FROM 'portræt' THEN RAISE EXCEPTION 'VERIFY_FAILED: media-slags — »foto« blev til »%«, ikke portræt', v_slags; END IF;
  UPDATE public.media SET slags = 'portraet' WHERE id = v_id RETURNING slags INTO v_slags;
  IF v_slags IS DISTINCT FROM 'portræt' THEN RAISE EXCEPTION 'VERIFY_FAILED: media-slags — »portraet« blev til »%«, ikke portræt', v_slags; END IF;
  UPDATE public.media SET slags = 'segl' WHERE id = v_id RETURNING slags INTO v_slags;
  IF v_slags IS DISTINCT FROM 'segl' THEN RAISE EXCEPTION 'VERIFY_FAILED: media-slags — »segl« blev til »%«', v_slags; END IF;
  -- Ukendt, NULL og tom afvises med 23514 og strengen, klienterne matcher på.
  FOREACH v_slags IN ARRAY ARRAY['tegning', NULL, '', '  '] LOOP
    v_state := NULL;
    BEGIN
      INSERT INTO public.media(slags, titel) VALUES (v_slags, '__verify_media_slags__');
    EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    END;
    IF v_state IS NULL OR strpos(v_msg, 'MEDIA_SLAGS_UKENDT') <> 1 THEN
      RAISE EXCEPTION 'VERIFY_FAILED: media-slags — INSERT med slags »%« blev ikke afvist med 23514 MEDIA_SLAGS_UKENDT', v_slags;
    END IF;
    v_state := NULL;
    BEGIN
      UPDATE public.media SET slags = v_slags WHERE id = v_id;
    EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    END;
    IF v_state IS NULL OR strpos(v_msg, 'MEDIA_SLAGS_UKENDT') <> 1 THEN
      RAISE EXCEPTION 'VERIFY_FAILED: media-slags — UPDATE til slags »%« blev ikke afvist med 23514 MEDIA_SLAGS_UKENDT', v_slags;
    END IF;
  END LOOP;
  -- (5) Fortryd skriver hele den gamle række tilbage (_version_upsert_row). Bærer snapshottet en gammel værdi (som 132
  -- hændelser i prod), oversættes den, og fortrydelsen lykkes uden at sætte motivet tilbage til en teknik.
  PERFORM set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
  INSERT INTO auth.users(id, email) VALUES ('00000000-0000-0000-0000-000000000001', 'db-verify@test.invalid')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id, rolle, email) VALUES ('00000000-0000-0000-0000-000000000001', 'redaktion', 't@x')
    ON CONFLICT (id) DO UPDATE SET rolle = 'redaktion';
  PERFORM set_config('app.change_set_id', '', true);
  PERFORM red_opdater_media(v_id, '__verify_media_slags_ny__');
  SELECT max(id) INTO v_cs FROM change_set;
  UPDATE change_event SET foer = jsonb_set(foer, '{slags}', '"maleri"')
   WHERE change_set_id = v_cs AND tabel = 'media' AND foer->>'slags' = 'segl';
  GET DIAGNOSTICS v_antal = ROW_COUNT;
  IF v_antal <> 1 THEN RAISE EXCEPTION 'VERIFY_FAILED: media-slags — fortryd-fixturen fandt % media-hændelser (vent 1)', v_antal; END IF;
  PERFORM set_config('app.change_set_id', '', true);
  PERFORM red_fortryd_change_set(v_cs, false);
  SELECT m.slags INTO v_slags FROM public.media m WHERE m.id = v_id AND m.titel = '__verify_media_slags__';
  IF v_slags IS DISTINCT FROM 'portræt' THEN
    RAISE EXCEPTION 'VERIFY_FAILED: media-slags — fortryd med »maleri« i snapshottet gav slags »%« (vent portræt, titel gendannet)', v_slags;
  END IF;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM = 'ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: media-slags — ordlisten er de seks koder; trg_media_slags oversætter gamle værdier (også ved fortryd) og afviser resten';
  ELSE RAISE; END IF;
END $verify_media_slags$;
-- END-VERIFY media-slags

-- BEGIN-VERIFY godser-fase1
-- ===== Godsernes oprydning, fase 1 (#471): ordforrådet estate_slags =====
-- Ordlisten er låst til en fast liste, som også står i ESTATE_SLAGS (packages/core/src/estates.ts). Et nyt gods-slags
-- kræver en vocab-række, en linje dér og en linje her. Skriver kun i en transaktion, der rulles tilbage.
DO $verify_godser_fase1$
DECLARE v_fejl text; v_antal bigint; v_state text; v_msg text;
  f regprocedure := to_regprocedure('private.validate_estate_slags()');
BEGIN
  -- (1) Præcis de fire koder med deres labels.
  WITH forventet(code, label) AS (VALUES
    ('gård','Gård'), ('grevskab','Grevskab'), ('baroni','Baroni'), ('stamhus','Stamhus')),
  faktisk AS (SELECT v.code, v.label FROM public.vocab v WHERE v.scheme = 'estate_slags')
  SELECT coalesce(string_agg(CASE WHEN f2.code IS NULL THEN ' mangler:'||e.code||'='||e.label
                                  ELSE ' uventet:'||f2.code||'='||coalesce(f2.label,'NULL') END, ''
                             ORDER BY coalesce(e.code, f2.code)), '')
    INTO v_fejl
    FROM forventet e FULL JOIN faktisk f2 ON e.code = f2.code AND e.label IS NOT DISTINCT FROM f2.label
   WHERE e.code IS NULL OR f2.code IS NULL;
  IF v_fejl <> '' THEN RAISE EXCEPTION 'VERIFY_FAILED: godser-fase1 — vocab estate_slags ≠ den faste liste:%', v_fejl; END IF;

  -- (2) Triggeren: BEFORE INSERT OR UPDATE OF slags, pr. række, aktiv, på den rigtige funktion.
  IF f IS NULL OR NOT EXISTS (
       SELECT 1 FROM pg_trigger t
        WHERE t.tgrelid = 'public.estate'::regclass AND t.tgname = 'trg_estate_slags' AND NOT t.tgisinternal
          AND t.tgenabled = 'O' AND t.tgfoid = f::oid
          AND t.tgtype = (1 | 2 | 4 | 16)   -- ROW | BEFORE | INSERT | UPDATE
          AND t.tgattr::text = (SELECT a.attnum::text FROM pg_attribute a
                                 WHERE a.attrelid = 'public.estate'::regclass AND a.attname = 'slags')
          AND t.tgqual IS NULL) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: godser-fase1 — trg_estate_slags mangler eller er ikke BEFORE INSERT OR UPDATE OF slags ON estate FOR EACH ROW → private.validate_estate_slags()';
  END IF;
  IF NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = f)
     OR (SELECT p.proconfig FROM pg_proc p WHERE p.oid = f) IS DISTINCT FROM ARRAY['search_path=public, pg_temp']
     OR EXISTS (SELECT 1 FROM pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                 WHERE p.oid = f AND a.grantee = 0)
     OR has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE')
     OR (EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') AND has_function_privilege('service_role', f, 'EXECUTE')) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: godser-fase1 — validate_estate_slags er ikke DEFINER med fast search_path eller kan kaldes af en klientrolle';
  END IF;

  -- (3) Data: ingen estate-række med en slags uden for ordlisten (NULL er tilladt).
  SELECT count(*) INTO v_antal FROM public.estate e
   WHERE e.slags IS NOT NULL AND e.slags NOT IN (SELECT v.code FROM public.vocab v WHERE v.scheme = 'estate_slags');
  IF v_antal <> 0 THEN RAISE EXCEPTION 'VERIFY_FAILED: godser-fase1 — % estate-rækker har en slags uden for ordlisten', v_antal; END IF;

  -- (4) Adfærd: kendt og NULL lykkes, ukendt afvises med 23514 ESTATE_SLAGS_UKENDT.
  INSERT INTO public.estate(navn, slags) VALUES ('__verify_godser_fase1__', 'grevskab');
  INSERT INTO public.estate(navn, slags) VALUES ('__verify_godser_fase1__', NULL);
  BEGIN
    INSERT INTO public.estate(navn, slags) VALUES ('__verify_godser_fase1__', 'gods');
  EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;
  IF v_state IS NULL OR strpos(v_msg, 'ESTATE_SLAGS_UKENDT') <> 1 THEN
    RAISE EXCEPTION 'VERIFY_FAILED: godser-fase1 — INSERT med slags »gods« blev ikke afvist med 23514 ESTATE_SLAGS_UKENDT';
  END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM = 'ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: godser-fase1 — estate_slags er de fire koder; trg_estate_slags afviser alt andet end NULL og ordlisten';
  ELSE RAISE; END IF;
END $verify_godser_fase1$;

-- ===== Godsernes oprydning, fase 1 (#471): relationerne hører_under og sammenlagt_i =====
-- Triggeren trg_estate_relation_vagt skal ligge med præcis denne form, og ingen relation må bryde reglerne (også ikke en,
-- der er skrevet uden om triggeren). MAJORAT-listen er den samme som MAJORAT_SLAGS i packages/core/src/estates.ts.
-- Skriver kun i en transaktion, der rulles tilbage.
DO $verify_godser_fase1_relation$
DECLARE v_antal bigint; v_state text; v_msg text; v_g bigint; v_m bigint; v_x bigint;
  f regprocedure := to_regprocedure('private.validate_estate_relation()');
BEGIN
  -- (1) Triggeren: BEFORE INSERT OR UPDATE (uden kolonneliste), pr. række, aktiv, med det brede WHEN.
  IF f IS NULL OR NOT EXISTS (
       SELECT 1 FROM pg_trigger t
        WHERE t.tgrelid = 'public.relation'::regclass AND t.tgname = 'trg_estate_relation_vagt' AND NOT t.tgisinternal
          AND t.tgenabled = 'O' AND t.tgfoid = f::oid
          AND t.tgtype = (1 | 2 | 4 | 16)   -- ROW | BEFORE | INSERT | UPDATE
          AND t.tgattr::text = ''
          AND t.tgqual IS NOT NULL
          AND pg_get_triggerdef(t.oid) LIKE $w$% WHEN (((new.subjekt_type = 'estate'::text) OR (new.objekt_type = 'estate'::text) OR (new.rolle = ANY (ARRAY['hører_under'::text, 'sammenlagt_i'::text])))) %$w$) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: godser-fase1 — trg_estate_relation_vagt mangler eller er ikke BEFORE INSERT OR UPDATE ON relation FOR EACH ROW WHEN (estate-ende eller hører_under/sammenlagt_i) → private.validate_estate_relation()';
  END IF;
  IF NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = f)
     OR (SELECT p.proconfig FROM pg_proc p WHERE p.oid = f) IS DISTINCT FROM ARRAY['search_path=public, pg_temp']
     OR EXISTS (SELECT 1 FROM pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                 WHERE p.oid = f AND a.grantee = 0)
     OR has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE')
     OR (EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') AND has_function_privilege('service_role', f, 'EXECUTE')) THEN
    RAISE EXCEPTION 'VERIFY_FAILED: godser-fase1 — validate_estate_relation er ikke DEFINER med fast search_path eller kan kaldes af en klientrolle';
  END IF;

  -- (2) Data: én optælling pr. regel.
  SELECT count(*) INTO v_antal FROM public.relation r
   WHERE r.rolle IN ('hører_under','sammenlagt_i')
     AND (r.subjekt_type IS DISTINCT FROM 'estate' OR r.objekt_type IS DISTINCT FROM 'estate'
          OR NOT EXISTS (SELECT 1 FROM public.estate e WHERE e.id = r.subjekt_id)
          OR NOT EXISTS (SELECT 1 FROM public.estate e WHERE e.id = r.objekt_id));
  IF v_antal <> 0 THEN RAISE EXCEPTION 'VERIFY_FAILED: godser-fase1 — % hører_under/sammenlagt_i-relationer har en ende, der ikke er et eksisterende gods', v_antal; END IF;
  SELECT count(*) INTO v_antal FROM public.relation r
   WHERE r.rolle IN ('hører_under','sammenlagt_i') AND r.subjekt_type = r.objekt_type AND r.subjekt_id = r.objekt_id;
  IF v_antal <> 0 THEN RAISE EXCEPTION 'VERIFY_FAILED: godser-fase1 — % hører_under/sammenlagt_i-relationer peger på sig selv', v_antal; END IF;
  SELECT count(*) INTO v_antal FROM public.relation r
    JOIN public.estate s ON r.subjekt_type = 'estate' AND s.id = r.subjekt_id
    JOIN public.estate o ON r.objekt_type = 'estate' AND o.id = r.objekt_id
   WHERE r.rolle = 'hører_under'
     AND (s.slags IS DISTINCT FROM 'gård' OR o.slags IS NULL OR o.slags NOT IN ('grevskab','baroni','stamhus'));
  IF v_antal <> 0 THEN RAISE EXCEPTION 'VERIFY_FAILED: godser-fase1 — % hører_under-relationer er ikke gård → grevskab/baroni/stamhus', v_antal; END IF;
  SELECT count(*) INTO v_antal FROM (
    SELECT r.subjekt_id FROM public.relation r WHERE r.rolle = 'sammenlagt_i' AND r.subjekt_type = 'estate'
     GROUP BY r.subjekt_id HAVING count(*) > 1) x;
  IF v_antal <> 0 THEN RAISE EXCEPTION 'VERIFY_FAILED: godser-fase1 — % godser er lagt sammen mere end ét sted', v_antal; END IF;
  SELECT count(*) INTO v_antal FROM public.relation r
   WHERE r.rolle = 'sammenlagt_i' AND r.objekt_type = 'estate'
     AND EXISTS (SELECT 1 FROM public.relation r2 WHERE r2.rolle = 'sammenlagt_i' AND r2.subjekt_type = 'estate'
                    AND r2.subjekt_id = r.objekt_id AND r2.id <> r.id);
  IF v_antal <> 0 THEN RAISE EXCEPTION 'VERIFY_FAILED: godser-fase1 — % sammenlagt_i-relationer danner en kæde (målet er selv sammenlagt)', v_antal; END IF;
  -- En sammenlagt række har ingen andre relationer end sin egen sammenlagt_i (ingen ejerforhold, billeder, hører_under).
  SELECT count(*) INTO v_antal FROM public.relation r
   WHERE r.rolle <> 'sammenlagt_i'
     AND (EXISTS (SELECT 1 FROM public.relation s WHERE s.rolle = 'sammenlagt_i' AND s.subjekt_type = 'estate'
                     AND r.subjekt_type = 'estate' AND s.subjekt_id = r.subjekt_id)
          OR EXISTS (SELECT 1 FROM public.relation s WHERE s.rolle = 'sammenlagt_i' AND s.subjekt_type = 'estate'
                     AND r.objekt_type = 'estate' AND s.subjekt_id = r.objekt_id));
  IF v_antal <> 0 THEN RAISE EXCEPTION 'VERIFY_FAILED: godser-fase1 — % relationer peger på en sammenlagt række', v_antal; END IF;

  -- (3) Adfærd: lovlig hører_under og sammenlagt_i lykkes; kæde og kobling til en sammenlagt række afvises.
  INSERT INTO public.estate(navn, slags) VALUES ('__verify_godser_fase1_g__','gård') RETURNING id INTO v_g;
  INSERT INTO public.estate(navn, slags) VALUES ('__verify_godser_fase1_m__','stamhus') RETURNING id INTO v_m;
  INSERT INTO public.estate(navn, slags) VALUES ('__verify_godser_fase1_x__',NULL) RETURNING id INTO v_x;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('estate',v_g,'estate',v_m,'hører_under');
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('estate',v_x,'estate',v_m,'sammenlagt_i');
  BEGIN
    INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('estate',v_m,'estate',v_g,'sammenlagt_i');
  EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;
  IF v_state IS NULL OR strpos(v_msg, 'ESTATE_SAMMENLAGT_KAEDE') <> 1 THEN
    RAISE EXCEPTION 'VERIFY_FAILED: godser-fase1 — sammenlagt_i af en række, der er mål for en sammenlægning, blev ikke afvist med ESTATE_SAMMENLAGT_KAEDE';
  END IF;
  v_state := NULL; v_msg := NULL;
  BEGIN
    INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES ('estate',v_g,'estate',v_x,'nabo_til');
  EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;
  IF v_state IS NULL OR strpos(v_msg, 'ESTATE_ER_SAMMENLAGT') <> 1 THEN
    RAISE EXCEPTION 'VERIFY_FAILED: godser-fase1 — en kobling til en sammenlagt række blev ikke afvist med ESTATE_ER_SAMMENLAGT';
  END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM = 'ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: godser-fase1 — trg_estate_relation_vagt håndhæver hører_under (gård → majorat) og sammenlagt_i (ingen kæde, ingen kobling til en sammenlagt række); 0 relationer bryder reglerne';
  ELSE RAISE; END IF;
END $verify_godser_fase1_relation$;
-- END-VERIFY godser-fase1
