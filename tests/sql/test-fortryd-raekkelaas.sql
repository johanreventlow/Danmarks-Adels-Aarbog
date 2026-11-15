-- Kodereview 36 K5: den generiske fortrydelse (red_fortryd_change_set) må aldrig stille overskrive en samtidig nyere
-- ændring. Tre forløb med to sessioner (dblink):
-- (a) T2 gemmer en ny værdi og holder sin transaktion åben; T1 starter fortrydelsen og skal vente; efter T2's COMMIT
--     afviser T1 med divergens, og T2's værdi står (før rettelsen: T1 så den gamle committede værdi, ventede på sin
--     UPDATE og overskrev T2's værdi uden divergens).
-- (b) T1 fortryder og holder transaktionen åben; T2's ændring venter og lander efter fortrydelsen.
-- (c) to samtidige fortrydelser af samme sæt, den anden med p_force: den anden venter på sættets række og afvises som
--     allerede fortrudt (før rettelsen: to reversal-sæt, sættet fortrudt to gange).
-- Opsætningen committes: kør testen i en ENGANGSBASE (CI: evidence-promotion-db, frisk schema-sti, ci_k36_laase) og kun
-- én gang pr. base. Alt syntetisk.
\set ON_ERROR_STOP on
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions;
SET search_path TO public, extensions, pg_catalog;

BEGIN;
INSERT INTO auth.users(id,email) VALUES ('36050000-0000-4000-8000-000000000001','k5@test.invalid');
INSERT INTO profiles(id,rolle,email) VALUES ('36050000-0000-4000-8000-000000000001','redaktion','k5@test.invalid');
INSERT INTO person(id,levende,privat,status) VALUES
  (-360501,false,false,'k5 a'),(-360502,false,false,'k5 b'),(-360503,false,false,'k5 c');
COMMIT;
SELECT set_config('request.jwt.claim.sub','36050000-0000-4000-8000-000000000001',false);
SELECT public.red_set_koen(-360501,'mand');
SELECT public.red_set_koen(-360502,'mand');
SELECT public.red_set_koen(-360503,'mand');

CREATE TEMP TABLE k5(k text PRIMARY KEY, v text);
INSERT INTO k5 SELECT 'cs_'||subjekt_id::text, max(id)::text FROM public.change_set
 WHERE operation='red_set_koen' AND subjekt_type='person' AND subjekt_id IN (-360501,-360502,-360503) GROUP BY subjekt_id;
CREATE FUNCTION pg_temp.k5(p_k text) RETURNS text LANGUAGE sql AS $$ SELECT v FROM k5 WHERE k=p_k $$;
CREATE FUNCTION pg_temp.k5_conn() RETURNS text LANGUAGE sql AS $$
  SELECT format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),
                split_part(current_setting('unix_socket_directories'),',',1)) $$;
-- Åbn en redaktør-session (READ COMMITTED, authenticated) under navnet p_name.
CREATE FUNCTION pg_temp.k5_open(p_name text) RETURNS int LANGUAGE plpgsql AS $$
DECLARE v_pid int;
BEGIN
  PERFORM dblink_connect(p_name,pg_temp.k5_conn());
  PERFORM dblink_exec(p_name,'BEGIN ISOLATION LEVEL READ COMMITTED');
  PERFORM * FROM dblink(p_name,$q$SELECT set_config('request.jwt.claim.sub','36050000-0000-4000-8000-000000000001',true)$q$) AS t(x text);
  PERFORM dblink_exec(p_name,'SET LOCAL ROLE authenticated');
  SELECT x INTO v_pid FROM dblink(p_name,'SELECT pg_backend_pid()') AS t(x int);
  RETURN v_pid;
END $$;
-- Vent højst 10 s på, at backend p_pid venter på en lås (pg_locks er live), eller at forespørgslen er færdig.
CREATE FUNCTION pg_temp.k5_wait_blocked(p_name text, p_pid int) RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE i int;
BEGIN
  FOR i IN 1..200 LOOP
    IF EXISTS (SELECT 1 FROM pg_locks l WHERE l.pid=p_pid AND NOT l.granted) THEN RETURN true; END IF;
    IF dblink_is_busy(p_name)=0 THEN RETURN false; END IF;
    PERFORM pg_sleep(0.05);
  END LOOP;
  RETURN false;
END $$;
-- Hent resultatet af en async forespørgsel og afslut transaktionen; returnér fejlteksten (NULL = lykkedes).
CREATE FUNCTION pg_temp.k5_finish(p_name text) RETURNS text LANGUAGE plpgsql AS $$
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

-- (a) T2 holder en nyere ændring; T1's fortrydelse skal vente og derefter afvise.
DO $k5_a$
DECLARE v_t1 int; v_blocked boolean; v_err text; v_koen text;
BEGIN
  PERFORM pg_temp.k5_open('k5_a_t2');
  PERFORM * FROM dblink('k5_a_t2','SELECT public.red_set_koen(-360501,''kvinde'')::text') AS t(x text);
  v_t1:=pg_temp.k5_open('k5_a_t1');
  PERFORM dblink_send_query('k5_a_t1',format('SELECT public.red_fortryd_change_set(%s)::text',pg_temp.k5('cs_-360501')));
  v_blocked:=pg_temp.k5_wait_blocked('k5_a_t1',v_t1);
  PERFORM dblink_exec('k5_a_t2','COMMIT');
  PERFORM dblink_disconnect('k5_a_t2');
  v_err:=pg_temp.k5_finish('k5_a_t1');
  SELECT koen INTO v_koen FROM public.person WHERE id=-360501;
  IF v_koen IS DISTINCT FROM 'kvinde' THEN
    RAISE EXCEPTION 'K5_TEST_FAILED: (a) T2''s nyere værdi blev overskrevet (koen=%, T1 ventede: %, T1-fejl: %)',
      coalesce(v_koen,'NULL'),v_blocked,coalesce(v_err,'ingen');
  END IF;
  IF v_err IS NULL OR v_err NOT LIKE '%nyere ændring rører%' THEN
    RAISE EXCEPTION 'K5_TEST_FAILED: (a) T1 afviste ikke med divergens (%)',coalesce(v_err,'ingen fejl');
  END IF;
  IF NOT v_blocked THEN RAISE EXCEPTION 'K5_TEST_FAILED: (a) T1 ventede ikke på T2'; END IF;
  IF EXISTS (SELECT 1 FROM public.change_set WHERE reverterer_id=pg_temp.k5('cs_-360501')::bigint) THEN
    RAISE EXCEPTION 'K5_TEST_FAILED: (a) en afvist fortrydelse efterlod et reversal-sæt';
  END IF;
  RAISE NOTICE 'OK: (a) T1 ventede på T2 og afviste med divergens; T2''s værdi står';
END $k5_a$;

-- (b) T1 fortryder først og holder låsene; T2's ændring venter og lander bagefter.
DO $k5_b$
DECLARE v_t2 int; v_blocked boolean; v_err text; v_koen text;
BEGIN
  PERFORM pg_temp.k5_open('k5_b_t1');
  PERFORM * FROM dblink('k5_b_t1',format('SELECT public.red_fortryd_change_set(%s)::text',pg_temp.k5('cs_-360502'))) AS t(x text);
  v_t2:=pg_temp.k5_open('k5_b_t2');
  PERFORM dblink_send_query('k5_b_t2','SELECT public.red_set_koen(-360502,''kvinde'')::text');
  v_blocked:=pg_temp.k5_wait_blocked('k5_b_t2',v_t2);
  PERFORM dblink_exec('k5_b_t1','COMMIT');
  PERFORM dblink_disconnect('k5_b_t1');
  v_err:=pg_temp.k5_finish('k5_b_t2');
  SELECT koen INTO v_koen FROM public.person WHERE id=-360502;
  IF NOT v_blocked OR v_err IS NOT NULL OR v_koen IS DISTINCT FROM 'kvinde' THEN
    RAISE EXCEPTION 'K5_TEST_FAILED: (b) T2 ventede: %, T2-fejl: %, koen=%',v_blocked,coalesce(v_err,'ingen'),coalesce(v_koen,'NULL');
  END IF;
  RAISE NOTICE 'OK: (b) T2 ventede på fortrydelsen og landede bagefter';
END $k5_b$;

-- (c) To samtidige fortrydelser af samme sæt; den anden (med p_force) venter på sættets række og afvises.
DO $k5_c$
DECLARE v_t2 int; v_blocked boolean; v_err text; v_n bigint;
BEGIN
  PERFORM pg_temp.k5_open('k5_c_t1');
  PERFORM * FROM dblink('k5_c_t1',format('SELECT public.red_fortryd_change_set(%s)::text',pg_temp.k5('cs_-360503'))) AS t(x text);
  v_t2:=pg_temp.k5_open('k5_c_t2');
  PERFORM dblink_send_query('k5_c_t2',format('SELECT public.red_fortryd_change_set(%s,true)::text',pg_temp.k5('cs_-360503')));
  v_blocked:=pg_temp.k5_wait_blocked('k5_c_t2',v_t2);
  PERFORM dblink_exec('k5_c_t1','COMMIT');
  PERFORM dblink_disconnect('k5_c_t1');
  v_err:=pg_temp.k5_finish('k5_c_t2');
  SELECT count(*) INTO v_n FROM public.change_set WHERE reverterer_id=pg_temp.k5('cs_-360503')::bigint;
  IF v_n<>1 THEN
    RAISE EXCEPTION 'K5_TEST_FAILED: (c) sættet blev fortrudt % gange (T2 ventede: %, T2-fejl: %)',v_n,v_blocked,coalesce(v_err,'ingen');
  END IF;
  IF v_err IS NULL OR v_err NOT LIKE '%er allerede fortrudt%' THEN
    RAISE EXCEPTION 'K5_TEST_FAILED: (c) T2 afvistes ikke som allerede fortrudt (%)',coalesce(v_err,'ingen fejl');
  END IF;
  IF NOT v_blocked THEN RAISE EXCEPTION 'K5_TEST_FAILED: (c) T2 ventede ikke på T1'; END IF;
  RAISE NOTICE 'OK: (c) anden samtidige fortrydelse (p_force) ventede og afvistes som allerede fortrudt';
END $k5_c$;
\echo PASS test-fortryd-raekkelaas
