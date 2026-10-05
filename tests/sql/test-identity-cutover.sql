-- Trin 5a: cutover-blokken lukker klientvejen i et katalog, hvor den GAMLE kerne og wrapper findes med grants.
\set ON_ERROR_STOP on
BEGIN;
DROP FUNCTION IF EXISTS public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb);
CREATE FUNCTION public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb) RETURNS integer LANGUAGE sql AS 'SELECT 1';
CREATE FUNCTION public.red_afgoer_source_persona(uuid,integer,text,bigint,text) RETURNS integer LANGUAGE sql AS 'SELECT 1';
GRANT EXECUTE ON FUNCTION public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb) TO anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.red_afgoer_source_persona(uuid,integer,text,bigint,text) TO anon,authenticated,service_role;
\i :cutover
DO $cutover_assert$
DECLARE v_role text; v_sig text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY['public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb)',
                               'public.red_afgoer_source_persona(uuid,integer,text,bigint,text)'] LOOP
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      IF has_function_privilege(v_role,v_sig,'EXECUTE') THEN
        RAISE EXCEPTION 'IDENTITY_CUTOVER_TEST_FAILED: % kan stadig kalde %',v_role,v_sig;
      END IF;
    END LOOP;
  END LOOP;
  RAISE NOTICE 'OK: cutover-blokken lukker klientvejen i et prod-lignende katalog';
END $cutover_assert$;
ROLLBACK;
