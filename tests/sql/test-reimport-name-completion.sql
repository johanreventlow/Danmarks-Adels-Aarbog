\set ON_ERROR_STOP on

DO $catalog$
DECLARE v_signature text;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.red_lock_reimport_name_completion(text)','public.red_authorize_reimport_name_completion(text,uuid,text,text,jsonb,jsonb)',
    'public.red_preflight_reimport_name_completion(uuid,uuid,text,jsonb)','public.red_begin_reimport_name_completion(uuid,text,uuid)',
    'public.red_apply_reimport_name_completion(uuid,text,jsonb)','public.red_finalize_reimport_name_completion(uuid)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NULL THEN RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_RPC_MISSING: %',v_signature; END IF;
  END LOOP;
  IF to_regclass('private.reimport_name_completion_result') IS NULL THEN RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_RESULT_MISSING'; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='private' AND table_name='reimport_name_completion_result' AND column_name='profile_sha256') THEN RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_PROFILE_IDENTITY_MISSING'; END IF;
END $catalog$;

\ir reimport-writer-v2-bootstrap.sql

DO $lifecycle$
DECLARE v_auth uuid; v_preflight jsonb; v_batch uuid; v_result jsonb;
BEGIN
  IF public.narrative_record_contract_version()<>2 THEN RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_V2_BOOTSTRAP_FAILED'; END IF;
  v_auth:=public.red_authorize_reimport_name_completion(repeat('a',64),gen_random_uuid(),repeat('b',64),repeat('c',64),'{}'::jsonb,'{}'::jsonb)->>'authorization_id';
  v_preflight:=public.red_preflight_reimport_name_completion(v_auth,gen_random_uuid(),repeat('a',64),'{}'::jsonb);
  v_batch:=public.red_begin_reimport_name_completion(v_auth,repeat('a',64),gen_random_uuid());
  PERFORM public.red_apply_reimport_name_completion(v_batch,'fixture','{}'::jsonb);
  v_result:=public.red_finalize_reimport_name_completion(v_batch);
  IF v_result IS NULL THEN RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_LIFECYCLE_INVALID'; END IF;
END $lifecycle$;
