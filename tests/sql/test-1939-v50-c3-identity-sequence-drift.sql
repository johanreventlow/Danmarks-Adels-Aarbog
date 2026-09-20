\set ON_ERROR_STOP on

\if :{?task3_fixture_id}
\else
  \echo 'task3_fixture_id psql variable is required'
  \quit 2
\endif

-- Run only on a disposable pre-C3 baseline.  A negative fixture exercises the
-- sequence floor; a high positive fixture exercises catch-up from a newly
-- created, initially-behind identity sequence.
DO $precondition$
DECLARE
  v_identity_count integer;
BEGIN
  SELECT count(*) INTO v_identity_count
  FROM information_schema.columns
  WHERE table_schema='public'
    AND table_name IN ('relation','assertion','conclusion')
    AND column_name='id'
    AND is_identity='YES';
  IF v_identity_count <> 0 THEN
    RAISE EXCEPTION 'C3_SEQUENCE_DRIFT_REQUIRES_PRE_IDENTITY_BASELINE';
  END IF;
END $precondition$;

SET session_replication_role=replica;
INSERT INTO public.relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
VALUES (:'task3_fixture_id'::bigint,'person',-1939505201,'person',-1939505202,'task3_drift_seed');
INSERT INTO public.assertion(id,target_type,target_id,vaerdi_tekst,uforanderlig)
VALUES (:'task3_fixture_id'::bigint,'fact',-1939505291,'task3 drift seed',false);
INSERT INTO public.conclusion(id,target_type,target_id,valgt_assertion_id,status,blaastemplet_af)
VALUES (:'task3_fixture_id'::bigint,'fact',-1939505291,:'task3_fixture_id'::bigint,'afklaret','Task 3 drift seed');
RESET session_replication_role;

\ir ../../db-migrations-c3-identity.sql

SET session_replication_role=replica;
INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
VALUES ('person',-1939505203,'person',-1939505204,'task3_drift_first')
RETURNING id AS relation_id \gset task3_first_
INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst,uforanderlig)
VALUES ('fact',-1939505292,'task3 drift first',false)
RETURNING id AS assertion_id \gset task3_first_
INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status,blaastemplet_af)
VALUES ('fact',-1939505292,:'task3_first_assertion_id'::bigint,'afklaret','Task 3 drift first')
RETURNING id AS conclusion_id \gset task3_first_
RESET session_replication_role;

SELECT 1 / CASE WHEN :'task3_first_relation_id'::bigint
                           > greatest(:'task3_fixture_id'::bigint,0) THEN 1 ELSE 0 END
  AS relation_first_default_above_floor;
SELECT 1 / CASE WHEN :'task3_first_assertion_id'::bigint
                           > greatest(:'task3_fixture_id'::bigint,0) THEN 1 ELSE 0 END
  AS assertion_first_default_above_floor;
SELECT 1 / CASE WHEN :'task3_first_conclusion_id'::bigint
                           > greatest(:'task3_fixture_id'::bigint,0) THEN 1 ELSE 0 END
  AS conclusion_first_default_above_floor;

-- The complete additive artifact must be safely repeatable after sequences have
-- served values, and each table must continue strictly above its own maximum.
\ir ../../db-migrations-c3-identity.sql

SET session_replication_role=replica;
INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
VALUES ('person',-1939505205,'person',-1939505206,'task3_drift_second')
RETURNING id AS relation_id \gset task3_second_
INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst,uforanderlig)
VALUES ('fact',-1939505293,'task3 drift second',false)
RETURNING id AS assertion_id \gset task3_second_
INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status,blaastemplet_af)
VALUES ('fact',-1939505293,:'task3_second_assertion_id'::bigint,'afklaret','Task 3 drift second')
RETURNING id AS conclusion_id \gset task3_second_
RESET session_replication_role;

SELECT 1 / CASE WHEN :'task3_second_relation_id'::bigint
                           > :'task3_first_relation_id'::bigint THEN 1 ELSE 0 END
  AS relation_repeat_default_advances;
SELECT 1 / CASE WHEN :'task3_second_assertion_id'::bigint
                           > :'task3_first_assertion_id'::bigint THEN 1 ELSE 0 END
  AS assertion_repeat_default_advances;
SELECT 1 / CASE WHEN :'task3_second_conclusion_id'::bigint
                           > :'task3_first_conclusion_id'::bigint THEN 1 ELSE 0 END
  AS conclusion_repeat_default_advances;

DO $success$
BEGIN
  RAISE NOTICE 'OK: C3 identity sequences catch up from drift and remain repeatable';
END $success$;
