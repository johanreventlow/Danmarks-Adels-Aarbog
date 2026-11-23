-- Review 37 D9 + R37B-1 (#397): fortryd og sletning må ikke kunne låse hinanden fast (deadlock, 40P01).
-- Tre forløb med to-tre sessioner (dblink); en tredje session H holder en rækkelås, så rækkefølgen er deterministisk:
-- (a) D9: red_slet_oplysning har slettet konklusionen og venter på citationen (H); fortrydelsen af det sæt, der
--     oprettede oplysningen, starter derefter. Før rettelsen låste fortrydelsen assertion → citation → conclusion og
--     sletningen conclusion → citation → assertion: deadlock, når H slipper. Efter: fortrydelsen venter på den fælles
--     fortryd/slet-lås, sletningen lykkes, og fortrydelsen afviser bagefter med divergens.
-- (b) D9: mens en fortrydelse holder låsen (udført, ikke committet), venter hver slette-RPC på den, før den rører en
--     række (kaldt med ukendte id'er: de fejler først efter ventetiden).
-- (c) R37B-1: fortrydelsen af et sæt med et linjemedlemskab låser personen før medlemskabet, som writerne
--     (red_reverse_placement_membership: person → medlemskab). Før rettelsen låste den medlemskabet og fik personen sent
--     via triggeren (regen_person_visning): deadlock mod en writer, der holdt personen.
-- Opsætningen committes: kør testen i en ENGANGSBASE og kun én gang pr. base. Alt syntetisk.
\set ON_ERROR_STOP on
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions;
SET search_path TO public, extensions, pg_catalog;

BEGIN;
INSERT INTO auth.users(id,email) VALUES ('37090000-0000-4000-8000-000000000001','d9@test.invalid');
INSERT INTO profiles(id,rolle,email) VALUES ('37090000-0000-4000-8000-000000000001','redaktion','d9@test.invalid');
INSERT INTO person(id,levende,privat,status) VALUES
  (-370901,false,false,'d9 a'),(-370902,false,false,'d9 b'),(-370903,false,false,'d9 c');
INSERT INTO slaegt(id,navn,sorteringsnavn,slug) VALUES (-370901,'D9-slægt','D9-slægt','d9-slaegt-test');
INSERT INTO lineage(id,kode,navn,slaegtsnavn,slaegt_id) VALUES (-370901,'D9','D9-linjen','D9slægt',-370901);
COMMIT;
SELECT set_config('request.jwt.claim.sub','37090000-0000-4000-8000-000000000001',false);

CREATE TEMP TABLE d9(k text PRIMARY KEY, v text);
-- (a): ét sæt opretter fakta, oplysning, citation og konklusion på person -370901.
INSERT INTO d9 SELECT 'a_'||key, value FROM jsonb_each_text(public.red_upsert_fakta('person',-370901,'titel','D9-titel'));
INSERT INTO d9 SELECT 'a_cs', max(id)::text FROM public.change_set
 WHERE operation='red_upsert_fakta' AND subjekt_type='person' AND subjekt_id=-370901;
-- (b): et lille sæt, som fortrydes og holdes åbent.
SELECT public.red_set_koen(-370903,'mand');
INSERT INTO d9 SELECT 'b_cs', max(id)::text FROM public.change_set
 WHERE operation='red_set_koen' AND subjekt_type='person' AND subjekt_id=-370903;
-- (c): ét sæt indsætter linje- og slægtsmedlemskab på person -370902 (som promotionen; rule_version, så
-- red_reverse_placement_membership genkender rækken). Slægtsnavnet vises kun på en person med navn.
SELECT public.red_upsert_fakta('person',-370902,'navn','Dino');
BEGIN;
SELECT public.begin_change_set('d9_test_membership','D9-test: medlemskab','person',-370902);
INSERT INTO person_lineage_membership(person_id,lineage_id,role,source_basis) VALUES
  (-370902,-370901,'member',jsonb_build_object('rule_version','placement-membership-v1','slaegt_id',-370901,
                                               'persona_placement_id','d9'));
INSERT INTO person_slaegt_membership(person_id,slaegt_id,membership_kind,source_basis) VALUES
  (-370902,-370901,'editorial',jsonb_build_object('persona_placement_id','d9'));
INSERT INTO d9 VALUES ('c_cs', current_setting('app.change_set_id'));
COMMIT;
DO $pre$
BEGIN
  IF (SELECT visning_efternavn FROM person WHERE id=-370902) IS DISTINCT FROM 'D9slægt' THEN
    RAISE EXCEPTION 'D9_TEST_FAILED: opsætning (c): medlemskabet satte ikke slægtsnavnet (triggeren skal opdatere personen)';
  END IF;
  IF (SELECT count(*) FROM change_event WHERE change_set_id=(SELECT v FROM d9 WHERE k='c_cs')::bigint) <> 2 THEN
    RAISE EXCEPTION 'D9_TEST_FAILED: opsætning (c): sættet har ikke præcis to medlemskabs-events';
  END IF;
END $pre$;

CREATE FUNCTION pg_temp.d9(p_k text) RETURNS text LANGUAGE sql AS $$ SELECT v FROM d9 WHERE k=p_k $$;
CREATE FUNCTION pg_temp.d9_conn() RETURNS text LANGUAGE sql AS $$
  SELECT format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),
                split_part(current_setting('unix_socket_directories'),',',1)) $$;
-- Åbn en session under navnet p_name. p_redaktor: redaktør (authenticated + jwt); ellers ejeren (H's rækkelås).
CREATE FUNCTION pg_temp.d9_open(p_name text, p_redaktor boolean DEFAULT true) RETURNS int LANGUAGE plpgsql AS $$
DECLARE v_pid int;
BEGIN
  PERFORM dblink_connect(p_name,pg_temp.d9_conn());
  PERFORM dblink_exec(p_name,'BEGIN ISOLATION LEVEL READ COMMITTED');
  PERFORM dblink_exec(p_name,'SET LOCAL deadlock_timeout=''100ms''');
  IF p_redaktor THEN
    PERFORM * FROM dblink(p_name,$q$SELECT set_config('request.jwt.claim.sub','37090000-0000-4000-8000-000000000001',true)$q$) AS t(x text);
    PERFORM dblink_exec(p_name,'SET LOCAL ROLE authenticated');
  END IF;
  SELECT x INTO v_pid FROM dblink(p_name,'SELECT pg_backend_pid()') AS t(x int);
  RETURN v_pid;
END $$;
-- Vent højst 10 s på, at backend p_pid venter på en lås; returnér låsetypen (NULL: forespørgslen blev færdig først).
CREATE FUNCTION pg_temp.d9_wait_blocked(p_name text, p_pid int) RETURNS text LANGUAGE plpgsql AS $$
DECLARE i int; v_typ text;
BEGIN
  FOR i IN 1..200 LOOP
    SELECT l.locktype INTO v_typ FROM pg_locks l WHERE l.pid=p_pid AND NOT l.granted LIMIT 1;
    IF v_typ IS NOT NULL THEN RETURN v_typ; END IF;
    IF dblink_is_busy(p_name)=0 THEN RETURN NULL; END IF;
    PERFORM pg_sleep(0.05);
  END LOOP;
  RETURN NULL;
END $$;
-- Hent resultatet af en async forespørgsel og afslut transaktionen; returnér fejlteksten (NULL = lykkedes).
CREATE FUNCTION pg_temp.d9_finish(p_name text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_err text;
BEGIN
  BEGIN
    PERFORM * FROM dblink_get_result(p_name) AS t(x text);
    PERFORM * FROM dblink_get_result(p_name) AS t(x text);
    PERFORM dblink_exec(p_name,'COMMIT');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    BEGIN PERFORM dblink_exec(p_name,'ROLLBACK'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END;
  PERFORM dblink_disconnect(p_name);
  RETURN v_err;
END $$;

-- (a) Sletningen først (holdt ved citationen), derefter fortrydelsen.
DO $d9_a$
DECLARE v_t1 int; v_t2 int; v_t2_typ text; v_t1_typ text; v_err1 text; v_err2 text;
BEGIN
  PERFORM pg_temp.d9_open('d9_a_h',false);
  PERFORM * FROM dblink('d9_a_h',format('SELECT 1 FROM public.citation WHERE id=%s FOR KEY SHARE',
                                         pg_temp.d9('a_citation_id'))) AS t(x int);
  v_t2:=pg_temp.d9_open('d9_a_t2');
  PERFORM dblink_send_query('d9_a_t2',format('SELECT public.red_slet_oplysning(%s)::text',pg_temp.d9('a_assertion_id')));
  v_t2_typ:=pg_temp.d9_wait_blocked('d9_a_t2',v_t2);
  IF v_t2_typ IS NULL THEN RAISE EXCEPTION 'D9_TEST_FAILED: (a) sletningen ventede ikke på H'; END IF;
  v_t1:=pg_temp.d9_open('d9_a_t1');
  PERFORM dblink_send_query('d9_a_t1',format('SELECT public.red_fortryd_change_set(%s)::text',pg_temp.d9('a_cs')));
  v_t1_typ:=pg_temp.d9_wait_blocked('d9_a_t1',v_t1);
  PERFORM dblink_exec('d9_a_h','COMMIT');
  PERFORM dblink_disconnect('d9_a_h');
  v_err2:=pg_temp.d9_finish('d9_a_t2');
  v_err1:=pg_temp.d9_finish('d9_a_t1');
  IF coalesce(v_err1,'') LIKE '%deadlock%' OR coalesce(v_err2,'') LIKE '%deadlock%' THEN
    RAISE EXCEPTION 'D9_TEST_FAILED: (a) deadlock (fortryd: %, slet: %)',coalesce(v_err1,'ok'),coalesce(v_err2,'ok');
  END IF;
  IF v_t1_typ IS DISTINCT FROM 'advisory' THEN
    RAISE EXCEPTION 'D9_TEST_FAILED: (a) fortrydelsen ventede ikke på fortryd/slet-låsen (ventede på: %)',coalesce(v_t1_typ,'intet');
  END IF;
  IF v_err2 IS NOT NULL THEN RAISE EXCEPTION 'D9_TEST_FAILED: (a) sletningen fejlede: %',v_err2; END IF;
  IF v_err1 IS NULL OR v_err1 NOT LIKE '%nyere ændring rører%' THEN
    RAISE EXCEPTION 'D9_TEST_FAILED: (a) fortrydelsen afviste ikke med divergens (%)',coalesce(v_err1,'ingen fejl');
  END IF;
  IF EXISTS (SELECT 1 FROM public.assertion WHERE id=pg_temp.d9('a_assertion_id')::bigint) THEN
    RAISE EXCEPTION 'D9_TEST_FAILED: (a) oplysningen findes stadig';
  END IF;
  RAISE NOTICE 'OK: (a) fortrydelsen ventede på sletningen ved fortryd/slet-låsen; ingen deadlock';
END $d9_a$;

-- (b) En åben fortrydelse holder låsen; hver slette-RPC venter på den før første rækkelås.
DO $d9_b$
DECLARE v_kald text[] := ARRAY[
    'SELECT public.red_slet_oplysning(-1)::text',
    'SELECT public.red_slet_relation(-1)::text',
    'SELECT public.red_fjern_samme_som(-1)::text',
    'SELECT public.red_fjern_ikke_samme_som(-1)::text',
    'SELECT public.red_slet_person(-1)::text',
    'SELECT public.red_slet_familie_link(-1,-1,''barn'')::text'];
  i int; v_pid int; v_typ text; v_err text;
BEGIN
  PERFORM pg_temp.d9_open('d9_b_t1');
  PERFORM * FROM dblink('d9_b_t1',format('SELECT public.red_fortryd_change_set(%s)::text',pg_temp.d9('b_cs'))) AS t(x text);
  FOR i IN 1..array_length(v_kald,1) LOOP
    v_pid:=pg_temp.d9_open('d9_b_s'||i);
    PERFORM dblink_send_query('d9_b_s'||i,v_kald[i]);
    v_typ:=pg_temp.d9_wait_blocked('d9_b_s'||i,v_pid);
    IF v_typ IS DISTINCT FROM 'advisory' THEN
      v_err:=pg_temp.d9_finish('d9_b_s'||i);
      RAISE EXCEPTION 'D9_TEST_FAILED: (b) % ventede ikke på fortryd/slet-låsen (ventede på: %, fejl: %)',
        v_kald[i],coalesce(v_typ,'intet'),coalesce(v_err,'ingen');
    END IF;
  END LOOP;
  PERFORM dblink_exec('d9_b_t1','COMMIT');
  PERFORM dblink_disconnect('d9_b_t1');
  FOR i IN 1..array_length(v_kald,1) LOOP
    v_err:=pg_temp.d9_finish('d9_b_s'||i);
    IF coalesce(v_err,'') LIKE '%deadlock%' THEN RAISE EXCEPTION 'D9_TEST_FAILED: (b) deadlock i %',v_kald[i]; END IF;
  END LOOP;
  RAISE NOTICE 'OK: (b) alle % slette-RPC''er ventede på en åben fortrydelse',array_length(v_kald,1);
END $d9_b$;

-- (c) Fortrydelsen af medlemskabssættet først (holdt ved slægtsmedlemskabet), derefter writeren person → medlemskab.
DO $d9_c$
DECLARE v_t1 int; v_t2 int; v_t1_typ text; v_t2_typ text; v_err1 text; v_err2 text;
BEGIN
  PERFORM pg_temp.d9_open('d9_c_h',false);
  PERFORM * FROM dblink('d9_c_h','SELECT 1 FROM public.person_slaegt_membership WHERE person_id=-370902 AND slaegt_id=-370901 FOR KEY SHARE') AS t(x int);
  v_t1:=pg_temp.d9_open('d9_c_t1');
  PERFORM dblink_send_query('d9_c_t1',format('SELECT public.red_fortryd_change_set(%s)::text',pg_temp.d9('c_cs')));
  v_t1_typ:=pg_temp.d9_wait_blocked('d9_c_t1',v_t1);
  IF v_t1_typ IS NULL THEN RAISE EXCEPTION 'D9_TEST_FAILED: (c) fortrydelsen ventede ikke på H'; END IF;
  v_t2:=pg_temp.d9_open('d9_c_t2');
  PERFORM dblink_send_query('d9_c_t2','SELECT public.red_reverse_placement_membership(-370902,-370901,''D9-test'')::text');
  v_t2_typ:=pg_temp.d9_wait_blocked('d9_c_t2',v_t2);
  PERFORM dblink_exec('d9_c_h','COMMIT');
  PERFORM dblink_disconnect('d9_c_h');
  v_err1:=pg_temp.d9_finish('d9_c_t1');
  v_err2:=pg_temp.d9_finish('d9_c_t2');
  IF coalesce(v_err1,'') LIKE '%deadlock%' OR coalesce(v_err2,'') LIKE '%deadlock%' THEN
    RAISE EXCEPTION 'D9_TEST_FAILED: (c) deadlock (fortryd: %, writer: %)',coalesce(v_err1,'ok'),coalesce(v_err2,'ok');
  END IF;
  IF v_t2_typ IS NULL THEN RAISE EXCEPTION 'D9_TEST_FAILED: (c) writeren ventede ikke på fortrydelsen'; END IF;
  IF v_err1 IS NOT NULL THEN RAISE EXCEPTION 'D9_TEST_FAILED: (c) fortrydelsen fejlede: %',v_err1; END IF;
  IF v_err2 IS NULL OR v_err2 NOT LIKE '%PLACEMENT_MEMBERSHIP_NOT_FOUND%' THEN
    RAISE EXCEPTION 'D9_TEST_FAILED: (c) writeren fandt stadig medlemskabet (%)',coalesce(v_err2,'ingen fejl');
  END IF;
  IF EXISTS (SELECT 1 FROM person_lineage_membership WHERE person_id=-370902)
     OR (SELECT visning_efternavn FROM person WHERE id=-370902) IS NOT NULL THEN
    RAISE EXCEPTION 'D9_TEST_FAILED: (c) fortrydelsen fjernede ikke medlemskabet og slægtsnavnet';
  END IF;
  RAISE NOTICE 'OK: (c) fortrydelsen låste personen før medlemskabet; writeren ventede; ingen deadlock';
END $d9_c$;
\echo PASS test-review37-d9-laaseorden
