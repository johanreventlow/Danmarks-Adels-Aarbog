-- TEST DATABASE ONLY. Never loaded by schema/migrations. No replacement of purge RPC.
-- A session-local GUC chooses a trigger pause; H owns advisory key 911011.
CREATE FUNCTION purge_test.pause() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('purge_test.pause',true)=TG_ARGV[0] THEN
    PERFORM pg_advisory_xact_lock(911011);
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER purge_test_l7 BEFORE UPDATE ON private.identity_mutation_generation
 FOR EACH ROW EXECUTE FUNCTION purge_test.pause('L7');
CREATE TRIGGER purge_test_l13 BEFORE INSERT ON private.person_purge_manifest
 FOR EACH ROW EXECUTE FUNCTION purge_test.pause('L13');
-- Stop a new fact after its BEFORE guard has acquired KEY SHARE but BEFORE
-- assertions/conclusions can call regen_person_visning and acquire a person lock.
-- Without this hook a removed KEY SHARE could be masked by regen's UPDATE lock.
CREATE TRIGGER purge_test_fact_insert AFTER INSERT ON public.fact
 FOR EACH ROW EXECUTE FUNCTION purge_test.pause('FACT_NEW');
-- For R37 only: append pause AFTER the original helper's person locks. Its original
-- body and ACL remain intact; only this disposable copy receives the extra statement.
DO $hook$
DECLARE d text; body text;
BEGIN
  SELECT pg_get_functiondef(oid),prosrc INTO d,body FROM pg_proc
    WHERE oid='private.lock_identity_people(bigint[])'::regprocedure;
  IF body !~ 'END[[:space:]]*$' THEN RAISE EXCEPTION 'TEST_HOOK_SHAPE'; END IF;
  EXECUTE replace(d,body,regexp_replace(body,'END[[:space:]]*$', $inject$
  IF current_setting('purge_test.pause',true)='L10' THEN
    PERFORM pg_advisory_xact_lock(911011);
  END IF;
END
$inject$));
  SELECT pg_get_functiondef(oid),prosrc INTO d,body FROM pg_proc
    WHERE oid='public.begin_change_set(text,text,text,bigint)'::regprocedure;
  EXECUTE replace(d,body,regexp_replace(body,'BEGIN', $inject$BEGIN
  IF current_setting('purge_test.pause_cs',true)='on' THEN
    PERFORM pg_advisory_xact_lock(911011);
  END IF;
$inject$));
END $hook$;
CREATE FUNCTION purge_test.hash() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r record; h text; result jsonb:='{}';
BEGIN
  FOR r IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p') AND NOT c.relispartition LOOP
    EXECUTE format('SELECT md5(coalesce(string_agg(to_jsonb(t)::text,E''\n'' ORDER BY to_jsonb(t)::text COLLATE "C"),'''')) FROM %I.%I t',
      r.nspname,r.relname) INTO h;
    result:=result||jsonb_build_object(r.nspname||'.'||r.relname,h);
  END LOOP;
  RETURN result;
END $$;
CREATE FUNCTION purge_test.gone() RETURNS boolean LANGUAGE sql AS $$
 SELECT NOT EXISTS(SELECT 1 FROM person WHERE id=purge_test.id('P'))
 AND NOT EXISTS(SELECT 1 FROM fact WHERE subjekt_type='person' AND subjekt_id=purge_test.id('P'))
 AND NOT EXISTS(SELECT 1 FROM relation WHERE (subjekt_type='person' AND subjekt_id=purge_test.id('P'))
   OR (objekt_type='person' AND objekt_id=purge_test.id('P')))
 AND NOT EXISTS(SELECT 1 FROM fact f JOIN purge_test.forventet e ON e.tabel='fact'
   AND e.handling='slet' AND e.pk @> jsonb_build_object('id',f.id))
 AND NOT EXISTS(SELECT 1 FROM assertion a JOIN purge_test.forventet e
   ON e.tabel='fact' AND e.handling='slet' AND a.target_type='fact' AND a.target_id=(e.pk->>'id')::bigint)
 AND NOT EXISTS(SELECT 1 FROM note a JOIN purge_test.forventet e
   ON e.tabel='fact' AND e.handling='slet' AND a.target_type='fact' AND a.target_id=(e.pk->>'id')::bigint)
$$;
