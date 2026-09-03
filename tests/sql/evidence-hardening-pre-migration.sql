\set ON_ERROR_STOP on

-- Test-only baseline for #154/#155.  It models the immediately preceding
-- contract on an otherwise disposable current schema, so the cumulative
-- migration path must actively restore every hardened invariant.  Never run
-- this file outside CI/a disposable database.
BEGIN;

DO $drop_truncate_guards$
DECLARE v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'extraction_run','source_rendition','source_record','source_record_occurrence',
    'source_record_anchor_event','source_record_revision_event','source_observation',
    'source_observation_text','source_mention','source_persona','source_persona_mention'
  ] LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS %I ON private.%I',
      'trg_' || v_table || '_append_only_truncate',v_table
    );
  END LOOP;
END $drop_truncate_guards$;

CREATE OR REPLACE FUNCTION private.validate_source_record_revision_event()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_predecessor_source bigint;
  v_successor_source bigint;
  v_expected_version integer;
BEGIN
  IF NEW.decision_status<>'proposed' AND (
    NEW.decided_by IS NULL
    OR nullif(btrim(NEW.decided_by_name),'') IS NULL
    OR NEW.evidence='{}'::jsonb
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_DECISION_METADATA_REQUIRED';
  END IF;
  PERFORM id FROM private.source_record
   WHERE id IN (NEW.predecessor_record_id,NEW.successor_record_id)
   ORDER BY id FOR UPDATE;
  SELECT source_id INTO v_predecessor_source FROM private.source_record WHERE id=NEW.predecessor_record_id;
  SELECT source_id INTO v_successor_source FROM private.source_record WHERE id=NEW.successor_record_id;
  IF v_predecessor_source IS DISTINCT FROM v_successor_source THEN
    RAISE EXCEPTION 'EVIDENCE_SOURCE_MISMATCH: source_record_revision_event';
  END IF;
  SELECT coalesce(max(version),0)+1 INTO v_expected_version
    FROM private.source_record_revision_event
   WHERE predecessor_record_id=NEW.predecessor_record_id
     AND successor_record_id=NEW.successor_record_id
     AND relation_kind=NEW.relation_kind;
  IF NEW.version <> v_expected_version THEN
    RAISE EXCEPTION 'EVIDENCE_EVENT_VERSION_CONFLICT: expected %, got %',v_expected_version,NEW.version;
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.red_decide_interpretation(
  p_interpretation_id uuid,
  p_expected_version integer,
  p_decision_status text,
  p_evidence jsonb
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_current private.interpretation%ROWTYPE;
  v_actor uuid := auth.uid();
  v_actor_name text;
  v_new_id uuid := gen_random_uuid();
BEGIN
  IF v_actor IS NULL OR public.current_rolle()<>'redaktion' THEN
    RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN';
  END IF;
  IF p_expected_version IS NULL OR p_expected_version<1 THEN
    RAISE EXCEPTION 'EVIDENCE_EXPECTED_VERSION_REQUIRED';
  END IF;
  SELECT coalesce(nullif(btrim(navn),''),nullif(btrim(email),''),v_actor::text)
    INTO v_actor_name FROM public.profiles WHERE id=v_actor;
  IF v_actor_name IS NULL THEN RAISE EXCEPTION 'EVIDENCE_ACTOR_REQUIRED'; END IF;
  IF p_decision_status NOT IN ('accepted','rejected','unresolved','superseded')
     OR jsonb_typeof(p_evidence)<>'object' OR p_evidence='{}'::jsonb THEN
    RAISE EXCEPTION 'EVIDENCE_DECISION_INVALID';
  END IF;
  SELECT * INTO v_current FROM private.interpretation
   WHERE id=p_interpretation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'EVIDENCE_INTERPRETATION_NOT_FOUND'; END IF;
  IF v_current.version<>p_expected_version OR EXISTS (
    SELECT 1 FROM private.interpretation newer
     WHERE newer.interpretation_key=v_current.interpretation_key
       AND newer.version>v_current.version
  ) THEN
    RAISE EXCEPTION 'EVIDENCE_INTERPRETATION_VERSION_CONFLICT';
  END IF;
  INSERT INTO private.interpretation(
    id,interpretation_key,version,source_id,source_persona_id,
    interpretation_kind,predicate,value,schema_version,derivation_kind,
    confidence,status,method,model_version,prompt_version,extraction_run_id,
    supersedes_id,decision_evidence,decided_by,decided_by_name,decided_at
  ) VALUES (
    v_new_id,v_current.interpretation_key,v_current.version+1,v_current.source_id,
    v_current.source_persona_id,v_current.interpretation_kind,v_current.predicate,
    v_current.value,v_current.schema_version,v_current.derivation_kind,
    v_current.confidence,p_decision_status,v_current.method,v_current.model_version,
    v_current.prompt_version,v_current.extraction_run_id,v_current.id,p_evidence,
    v_actor,v_actor_name,clock_timestamp()
  );
  INSERT INTO private.interpretation_observation(
    interpretation_id,observation_id,evidence_role,ordinal
  ) SELECT v_new_id,observation_id,evidence_role,ordinal
      FROM private.interpretation_observation
     WHERE interpretation_id=v_current.id;
  RETURN v_new_id;
END $$;

-- Reproduce the #154 failure mode: a later public red_* RPC has no explicit
-- authenticated grant and is left publicly callable by legacy defaults.
GRANT EXECUTE ON FUNCTION public.red_edit_oplysning(
  bigint,text,text,text
) TO PUBLIC;
REVOKE EXECUTE ON FUNCTION public.red_edit_oplysning(
  bigint,text,text,text
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.red_edit_oplysning(
  bigint,text,text,text
) TO service_role;

COMMIT;
