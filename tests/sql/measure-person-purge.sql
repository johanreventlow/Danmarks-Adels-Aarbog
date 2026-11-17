-- Kun mod en PROD-KOPI, aldrig produktion. Hele sletningen rulles tilbage.
-- psql -X -q -v ON_ERROR_STOP=1 -d <prod_kopi> -v pid=<person_id> -v actor=<redaktoer_uuid> -f tests/sql/measure-person-purge.sql
-- Output: preview_ms | purge_ms | storage_antal | personas_afvist | person_rest | manifest_rest.
\set ON_ERROR_STOP on
\set QUIET on
\set VERBOSITY terse
\set SHOW_CONTEXT never
\pset format unaligned
\pset tuples_only on
\pset fieldsep '|'
BEGIN;
SET LOCAL client_min_messages=error;
SELECT set_config('request.jwt.claim.sub',:'actor',true),set_config('app.change_set_id','',true) \g /dev/null
CREATE TEMP TABLE purge_measure_input(pid bigint) ON COMMIT DROP;
INSERT INTO purge_measure_input VALUES(:pid);
CREATE TEMP TABLE purge_measure_result(preview_ms numeric,purge_ms numeric,storage_antal bigint,personas_afvist bigint) ON COMMIT DROP;
DO $measure$
DECLARE v_p bigint:=(SELECT pid FROM purge_measure_input); v_start timestamptz; v_preview_ms numeric; v_purge_ms numeric;
  v_preview jsonb; v_result jsonb;
BEGIN
  SET LOCAL ROLE authenticated;
  v_start:=clock_timestamp();
  v_preview:=public.red_slet_person_helt_preview(v_p);
  v_preview_ms:=extract(epoch FROM clock_timestamp()-v_start)*1000;
  v_start:=clock_timestamp();
  v_result:=public.red_slet_person_helt(v_p,v_preview->>'sha256');
  v_purge_ms:=extract(epoch FROM clock_timestamp()-v_start)*1000;
  RESET ROLE;
  -- Tving også de deferred identitetsvagter inden målingens ROLLBACK.
  SET CONSTRAINTS ALL IMMEDIATE;
  INSERT INTO purge_measure_result VALUES(v_preview_ms,v_purge_ms,(v_result->>'storage_antal')::bigint,(v_result->>'personas_afvist')::bigint);
END $measure$;
SELECT round(preview_ms,1),round(purge_ms,1),storage_antal,personas_afvist,
  (SELECT count(*) FROM public.person WHERE id=(SELECT pid FROM purge_measure_input)),
  (SELECT count(*) FROM private.person_purge_manifest WHERE xid=pg_current_xact_id() AND backend_pid=pg_backend_pid())
FROM purge_measure_result;
ROLLBACK;
