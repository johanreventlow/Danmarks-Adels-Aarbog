-- Kodereview 36 K6: højst ét primært portræt pr. person.
-- (a) sæt A, skift til B, fortryd skiftet → A er primær igen; (a2) en fortrydelse, hvis mellemtrin har to flag (sættet
--     satte det nye flag FØR det ryddede det gamle), lykkes, fordi constraint'en er udskudt til COMMIT;
-- (b) to primære i én transaktion afvises ved COMMIT (exclusion constraint, SQLSTATE 23P01);
-- (c) to samtidige red_saet_portraet for samme person uden primært portræt: den anden venter på personlåsen og ender
--     som eneste primære.
-- Sessionerne i (b) og (c) går gennem dblink og ser kun committede data, så opsætningen committes: kør testen i en
-- ENGANGSBASE (CI: evidence-promotion-db, frisk schema-sti) og kun én gang pr. base. Alt syntetisk.
\set ON_ERROR_STOP on
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions;
SET search_path TO public, extensions, pg_catalog;

-- Opsætning (committes): redaktør, fire personer og to medier pr. person, alle med afbildet-relation uden flag.
BEGIN;
INSERT INTO auth.users(id,email) VALUES ('36060000-0000-4000-8000-000000000001','k6@test.invalid');
INSERT INTO profiles(id,rolle,email) VALUES ('36060000-0000-4000-8000-000000000001','redaktion','k6@test.invalid');
INSERT INTO person(id,levende,privat,status) VALUES
  (-360601,false,false,'k6 a'),(-360602,false,false,'k6 a2'),(-360603,false,false,'k6 b'),(-360604,false,false,'k6 c');
INSERT INTO media(id,slags,upload_status) VALUES
  (-360611,'foto','klar'),(-360612,'foto','klar'),(-360621,'foto','klar'),(-360622,'foto','klar'),
  (-360631,'foto','klar'),(-360632,'foto','klar'),(-360641,'foto','klar'),(-360642,'foto','klar');
INSERT INTO relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES
  ('person',-360601,'media',-360611,'afbildet'),('person',-360601,'media',-360612,'afbildet'),
  ('person',-360602,'media',-360621,'afbildet'),('person',-360602,'media',-360622,'afbildet'),
  ('person',-360603,'media',-360631,'afbildet'),('person',-360603,'media',-360632,'afbildet'),
  ('person',-360604,'media',-360641,'afbildet'),('person',-360604,'media',-360642,'afbildet');
COMMIT;

CREATE FUNCTION pg_temp.k6_primaer(p_person bigint) RETURNS bigint[] LANGUAGE sql AS $$
  SELECT coalesce(array_agg(objekt_id ORDER BY objekt_id),'{}') FROM public.relation
   WHERE subjekt_type='person' AND subjekt_id=p_person AND objekt_type='media' AND rolle='afbildet'
     AND kvalifikator ? 'primaer' $$;
CREATE FUNCTION pg_temp.k6_conn() RETURNS text LANGUAGE sql AS $$
  SELECT format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),
                split_part(current_setting('unix_socket_directories'),',',1)) $$;
SELECT set_config('request.jwt.claim.sub','36060000-0000-4000-8000-000000000001',false);

-- Constraint'en findes og er udskudt.
DO $k6_constraint$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.relation'::regclass AND conname='relation_hoejst_et_primaert_portraet'
                    AND contype='x' AND condeferrable AND condeferred) THEN
    RAISE EXCEPTION 'K6_TEST_FAILED: relation_hoejst_et_primaert_portraet mangler eller er ikke DEFERRABLE INITIALLY DEFERRED';
  END IF;
END $k6_constraint$;

-- (a) Sæt A, skift til B, fortryd skiftet: hver i sin egen transaktion, så constraint'en prøves ved hver COMMIT.
SELECT public.red_saet_portraet(-360601,-360611);
SELECT public.red_saet_portraet(-360601,-360612);
DO $k6_a_mid$
BEGIN
  IF pg_temp.k6_primaer(-360601)<>ARRAY[-360612]::bigint[] THEN
    RAISE EXCEPTION 'K6_TEST_FAILED: (a) skiftet efterlod %',pg_temp.k6_primaer(-360601);
  END IF;
END $k6_a_mid$;
SELECT public.red_fortryd_change_set((SELECT max(id) FROM public.change_set
  WHERE operation='red_saet_portraet' AND subjekt_type='person' AND subjekt_id=-360601));
DO $k6_a$
BEGIN
  IF pg_temp.k6_primaer(-360601)<>ARRAY[-360611]::bigint[] THEN
    RAISE EXCEPTION 'K6_TEST_FAILED: (a) fortrydelsen af skiftet efterlod %',pg_temp.k6_primaer(-360601);
  END IF;
  RAISE NOTICE 'OK: (a) sæt A, skift til B, fortryd skiftet → A er primær igen';
END $k6_a$;

-- (a2) Et sæt, der først satte det nye flag og derefter ryddede det gamle (mellemtrin med to flag, tilladt fordi
-- constraint'en er udskudt). Fortrydelsen kører i omvendt rækkefølge og har derfor også et mellemtrin med to flag;
-- den skal lykkes, og slutresultatet er ét flag.
SELECT public.red_saet_portraet(-360602,-360621);
BEGIN;
SELECT public.begin_change_set('k6_test_omvendt','K6-test: nyt flag før det gamle ryddes','person',-360602);
UPDATE public.relation SET kvalifikator='{"primaer":true}'::jsonb
 WHERE subjekt_type='person' AND subjekt_id=-360602 AND objekt_type='media' AND objekt_id=-360622 AND rolle='afbildet';
UPDATE public.relation SET kvalifikator=NULL
 WHERE subjekt_type='person' AND subjekt_id=-360602 AND objekt_type='media' AND objekt_id=-360621 AND rolle='afbildet';
COMMIT;
SELECT public.red_fortryd_change_set((SELECT max(id) FROM public.change_set WHERE operation='k6_test_omvendt'));
DO $k6_a2$
BEGIN
  IF pg_temp.k6_primaer(-360602)<>ARRAY[-360621]::bigint[] THEN
    RAISE EXCEPTION 'K6_TEST_FAILED: (a2) fortrydelsen efterlod %',pg_temp.k6_primaer(-360602);
  END IF;
  RAISE NOTICE 'OK: (a2) fortrydelse med mellemtrin med to flag lykkes (udskudt constraint)';
END $k6_a2$;

-- (b) To primære i én transaktion: UPDATE'en går igennem (udskudt), COMMIT afvises med exclusion_violation.
DO $k6_b$
DECLARE v_state text; v_err text;
BEGIN
  PERFORM dblink_connect('k6_b',pg_temp.k6_conn());
  PERFORM dblink_exec('k6_b','BEGIN');
  PERFORM dblink_exec('k6_b',$q$UPDATE public.relation SET kvalifikator='{"primaer":true}'::jsonb
    WHERE subjekt_type='person' AND subjekt_id=-360603 AND objekt_type='media' AND rolle='afbildet'$q$);
  BEGIN
    PERFORM dblink_exec('k6_b','COMMIT');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE, v_err=MESSAGE_TEXT;
  END;
  BEGIN PERFORM dblink_exec('k6_b','ROLLBACK'); EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM dblink_disconnect('k6_b');
  IF v_err IS NULL THEN
    RAISE EXCEPTION 'K6_TEST_FAILED: (b) to primære portrætter blev committet (%)',pg_temp.k6_primaer(-360603);
  END IF;
  IF v_err NOT LIKE '%relation_hoejst_et_primaert_portraet%' THEN
    RAISE EXCEPTION 'K6_TEST_FAILED: (b) COMMIT fejlede af en anden grund: % (%)',v_err,v_state;
  END IF;
  IF pg_temp.k6_primaer(-360603)<>'{}'::bigint[] THEN
    RAISE EXCEPTION 'K6_TEST_FAILED: (b) afvist transaktion efterlod %',pg_temp.k6_primaer(-360603);
  END IF;
  RAISE NOTICE 'OK: (b) to primære i én transaktion afvises ved COMMIT';
END $k6_b$;

-- (c) Session A sætter D1 og holder transaktionen åben; session B sætter D2 og skal vente på personlåsen.
CREATE TEMP TABLE k6_c(k text PRIMARY KEY, v text);
DO $k6_c_start$
DECLARE v_pid int; v_blocked boolean:=false; i int;
BEGIN
  PERFORM dblink_connect('k6_ca',pg_temp.k6_conn());
  PERFORM dblink_exec('k6_ca','BEGIN ISOLATION LEVEL READ COMMITTED');
  PERFORM * FROM dblink('k6_ca',$q$SELECT set_config('request.jwt.claim.sub','36060000-0000-4000-8000-000000000001',true)$q$) AS t(x text);
  PERFORM dblink_exec('k6_ca','SET LOCAL ROLE authenticated');
  PERFORM * FROM dblink('k6_ca','SELECT public.red_saet_portraet(-360604,-360641)::text') AS t(x text);
  PERFORM dblink_connect('k6_cb',pg_temp.k6_conn());
  PERFORM dblink_exec('k6_cb','BEGIN ISOLATION LEVEL READ COMMITTED');
  PERFORM * FROM dblink('k6_cb',$q$SELECT set_config('request.jwt.claim.sub','36060000-0000-4000-8000-000000000001',true)$q$) AS t(x text);
  PERFORM dblink_exec('k6_cb','SET LOCAL ROLE authenticated');
  SELECT x INTO v_pid FROM dblink('k6_cb','SELECT pg_backend_pid()') AS t(x int);
  PERFORM dblink_send_query('k6_cb','SELECT public.red_saet_portraet(-360604,-360642)::text');
  -- pg_locks er live (det er pg_stat_*-visningerne, der fryses i transaktionen); vent højst 10 s.
  FOR i IN 1..200 LOOP
    IF EXISTS (SELECT 1 FROM pg_locks l WHERE l.pid=v_pid AND NOT l.granted) THEN v_blocked:=true; EXIT; END IF;
    EXIT WHEN dblink_is_busy('k6_cb')=0;
    PERFORM pg_sleep(0.05);
  END LOOP;
  INSERT INTO k6_c VALUES ('blocked',v_blocked::text);
END $k6_c_start$;
DO $k6_c_end$
DECLARE v_err text;
BEGIN
  PERFORM dblink_exec('k6_ca','COMMIT');
  PERFORM dblink_disconnect('k6_ca');
  BEGIN
    PERFORM * FROM dblink_get_result('k6_cb') AS t(x text);
    PERFORM * FROM dblink_get_result('k6_cb') AS t(x text);
    PERFORM dblink_exec('k6_cb','COMMIT');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
  END;
  BEGIN PERFORM dblink_disconnect('k6_cb'); EXCEPTION WHEN OTHERS THEN NULL; END;
  IF pg_temp.k6_primaer(-360604)<>ARRAY[-360642]::bigint[] THEN
    RAISE EXCEPTION 'K6_TEST_FAILED: (c) efter to samtidige valg er de primære % (B ventede: %, B-fejl: %)',
      pg_temp.k6_primaer(-360604),(SELECT v FROM k6_c WHERE k='blocked'),coalesce(v_err,'ingen');
  END IF;
  IF (SELECT v FROM k6_c WHERE k='blocked')<>'true' THEN
    RAISE EXCEPTION 'K6_TEST_FAILED: (c) session B ventede ikke på personlåsen';
  END IF;
  IF v_err IS NOT NULL THEN
    RAISE EXCEPTION 'K6_TEST_FAILED: (c) session B fejlede: %',v_err;
  END IF;
  RAISE NOTICE 'OK: (c) to samtidige valg → B ventede på personlåsen og er eneste primære';
END $k6_c_end$;
\echo PASS test-portraet-primaer
