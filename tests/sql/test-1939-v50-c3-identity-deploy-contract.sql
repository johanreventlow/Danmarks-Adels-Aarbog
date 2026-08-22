\set ON_ERROR_STOP on

\if :{?task3_dsn}
\else
  \echo 'task3_dsn psql variable is required'
  \quit 2
\endif

DO $catalog$
DECLARE
  v_missing text[];
  v_unsafe text[];
BEGIN
  SELECT array_agg(table_name ORDER BY table_name)
    INTO v_missing
  FROM information_schema.columns
  WHERE table_schema='public'
    AND table_name IN ('relation','assertion','conclusion')
    AND column_name='id'
    AND (is_identity<>'YES' OR identity_generation<>'BY DEFAULT');
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'C3_IDENTITY_DEFAULT_CONTRACT_MISSING: %', v_missing;
  END IF;

  WITH expected(proname) AS (VALUES
    ('red_apply_1939_v50_name_completion'),
    ('red_upsert_fakta'),
    ('red_tilfoej_oplysning'),
    ('red_opret_fakta'),
    ('red_set_konklusion'),
    ('red_edit_oplysning'),
    ('red_relation'),
    ('red_samme_som'),
    ('red_ikke_samme_som'),
    ('red_tilfoej_relation'),
    ('_ensure_foraeldrefamilie_redaktionel'),
    ('red_tilfoej_foraeldre_paastand'),
    ('red_vaelg_foraeldre')
  )
  SELECT array_agg(e.proname ORDER BY e.proname)
    INTO v_missing
  FROM expected e
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname=e.proname
  );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'C3_IDENTITY_WRITER_MISSING: %', v_missing;
  END IF;

  SELECT array_agg(p.oid::regprocedure::text ORDER BY p.oid::regprocedure::text)
    INTO v_unsafe
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND p.proname=ANY(ARRAY[
      'red_apply_1939_v50_name_completion','red_upsert_fakta',
      'red_tilfoej_oplysning','red_opret_fakta','red_set_konklusion',
      'red_edit_oplysning','red_relation','red_samme_som',
      'red_ikke_samme_som','red_tilfoej_relation',
      '_ensure_foraeldrefamilie_redaktionel',
      'red_tilfoej_foraeldre_paastand','red_vaelg_foraeldre'
    ])
    AND regexp_replace(pg_get_functiondef(p.oid),'\s+',' ','g') ~*
      'max\s*\(\s*id\s*\)[^;]{0,160}FROM\s+(public\.)?(relation|assertion|conclusion)';
  IF v_unsafe IS NOT NULL THEN
    RAISE EXCEPTION 'C3_IDENTITY_MANUAL_ID_WRITER_REMAINS: %', v_unsafe;
  END IF;
END $catalog$;

CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions;

-- Committed setup is required because the remote dblink transaction must see
-- the people before it overlaps the local identity RPC.
BEGIN;
SELECT set_config('app.change_set_id','',false);
SELECT set_config('app.change_seq','',false);
DELETE FROM public.conclusion c
 WHERE c.target_type='relation' AND c.target_id IN (
   SELECT r.id FROM public.relation r
   WHERE r.subjekt_id BETWEEN -1939504204 AND -1939504201
      OR r.objekt_id BETWEEN -1939504204 AND -1939504201
 );
DELETE FROM public.assertion a
 WHERE a.target_type='relation' AND a.target_id IN (
   SELECT r.id FROM public.relation r
   WHERE r.subjekt_id BETWEEN -1939504204 AND -1939504201
      OR r.objekt_id BETWEEN -1939504204 AND -1939504201
 );
DELETE FROM public.relation r
 WHERE r.subjekt_id BETWEEN -1939504204 AND -1939504201
    OR r.objekt_id BETWEEN -1939504204 AND -1939504201;
DELETE FROM public.conclusion WHERE target_type='fact' AND target_id IN (-1939504291,-1939504292);
DELETE FROM public.citation WHERE assertion_id IN (
  SELECT id FROM public.assertion WHERE target_type='fact' AND target_id IN (-1939504291,-1939504292)
);
DELETE FROM public.assertion WHERE target_type='fact' AND target_id IN (-1939504291,-1939504292);
DELETE FROM public.fact WHERE id IN (-1939504291,-1939504292);
DELETE FROM public.person WHERE id BETWEEN -1939504204 AND -1939504201;
DELETE FROM public.profiles WHERE id='19395000-0000-4000-8000-000000000420';
DELETE FROM auth.users WHERE id='19395000-0000-4000-8000-000000000420';
COMMIT;

BEGIN;
INSERT INTO auth.users(id,email)
VALUES ('19395000-0000-4000-8000-000000000420','c3-id-deploy@test.invalid');
INSERT INTO public.profiles(id,email,rolle,navn)
VALUES ('19395000-0000-4000-8000-000000000420','c3-id-deploy@test.invalid','redaktion','C3 ID deploy test');
INSERT INTO public.person(id,levende,koen) VALUES
  (-1939504201,false,'ukendt'),(-1939504202,false,'ukendt'),
  (-1939504203,false,'ukendt'),(-1939504204,false,'ukendt');
INSERT INTO public.fact(id,subjekt_type,subjekt_id,faktatype) VALUES
  (-1939504291,'person',-1939504201,'deploy_test_a'),
  (-1939504292,'person',-1939504202,'deploy_test_b');
COMMIT;

SELECT set_config(
  'request.jwt.claim.sub',
  '19395000-0000-4000-8000-000000000420',
  false
);

SELECT extensions.dblink_connect('c3_default_writer', :'task3_dsn');
SELECT extensions.dblink_send_query(
  'c3_default_writer',
  $remote$
    WITH inserted AS (
      INSERT INTO public.relation(
        subjekt_type,subjekt_id,objekt_type,objekt_id,rolle
      ) VALUES ('person',-1939504203,'person',-1939504204,'bekendt_med')
      RETURNING id
    )
    SELECT id, pg_sleep(1) IS NULL AS completed FROM inserted
  $remote$
);
SELECT pg_sleep(0.2);

-- With the former max(id)+1 body this sees no committed remote row, chooses
-- the same ID, waits for the remote commit, and then fails on the primary key.
SELECT public.red_samme_som(-1939504201,-1939504202) AS same_relation_id
\gset c3_

SELECT id AS raw_relation_id
FROM extensions.dblink_get_result('c3_default_writer') AS t(id bigint, completed boolean)
\gset c3_
SELECT extensions.dblink_disconnect('c3_default_writer');

SELECT 1 / CASE
  WHEN :'c3_same_relation_id'::bigint = :'c3_raw_relation_id'::bigint THEN 0
  ELSE 1
END AS relation_ids_are_distinct;

SELECT (public.red_tilfoej_oplysning(
  -1939504291,'deploy assertion',NULL,NULL,NULL,NULL,NULL
)->>'assertion_id')::bigint AS assertion_id
\gset c3_
INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst,uforanderlig)
VALUES ('fact',-1939504292,'raw default assertion',false)
RETURNING id AS raw_assertion_id
\gset c3_

SELECT public.red_set_konklusion(:'c3_assertion_id'::bigint);
INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status,blaastemplet_af)
VALUES ('fact',-1939504292,:'c3_raw_assertion_id'::bigint,'afklaret','C3 deploy test')
RETURNING id AS raw_conclusion_id
\gset c3_

SELECT 1 / CASE
  WHEN :'c3_assertion_id'::bigint = :'c3_raw_assertion_id'::bigint THEN 0
  ELSE 1
END AS assertion_ids_are_distinct;
SELECT 1 / CASE
  WHEN EXISTS (
    SELECT 1 FROM public.conclusion
    WHERE target_type='fact' AND target_id=-1939504291
      AND valgt_assertion_id=:'c3_assertion_id'::bigint
  ) THEN 1
  ELSE 0
END AS conclusion_default_insert_exists;

SELECT set_config('app.change_set_id','',false);
SELECT set_config('app.change_seq','',false);
DELETE FROM public.conclusion c
 WHERE (c.target_type='relation' AND c.target_id IN (
          SELECT r.id FROM public.relation r
          WHERE r.subjekt_id BETWEEN -1939504204 AND -1939504201
             OR r.objekt_id BETWEEN -1939504204 AND -1939504201
        ))
    OR (c.target_type='fact' AND c.target_id IN (-1939504291,-1939504292));
DELETE FROM public.citation WHERE assertion_id IN (
  SELECT id FROM public.assertion
  WHERE (target_type='relation' AND target_id IN (
           SELECT r.id FROM public.relation r
           WHERE r.subjekt_id BETWEEN -1939504204 AND -1939504201
              OR r.objekt_id BETWEEN -1939504204 AND -1939504201
         ))
     OR (target_type='fact' AND target_id IN (-1939504291,-1939504292))
);
DELETE FROM public.assertion a
 WHERE (a.target_type='relation' AND a.target_id IN (
          SELECT r.id FROM public.relation r
          WHERE r.subjekt_id BETWEEN -1939504204 AND -1939504201
             OR r.objekt_id BETWEEN -1939504204 AND -1939504201
        ))
    OR (a.target_type='fact' AND a.target_id IN (-1939504291,-1939504292));
DELETE FROM public.relation r
 WHERE r.subjekt_id BETWEEN -1939504204 AND -1939504201
    OR r.objekt_id BETWEEN -1939504204 AND -1939504201;
DELETE FROM public.fact WHERE id IN (-1939504291,-1939504292);
DELETE FROM public.person WHERE id BETWEEN -1939504204 AND -1939504201;
DELETE FROM public.profiles WHERE id='19395000-0000-4000-8000-000000000420';
DELETE FROM auth.users WHERE id='19395000-0000-4000-8000-000000000420';

DO $success$
BEGIN
  RAISE NOTICE 'OK: C3 identity defaults are cross-writer collision safe';
END $success$;
