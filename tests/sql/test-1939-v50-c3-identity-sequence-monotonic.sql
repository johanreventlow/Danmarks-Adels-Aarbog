\set ON_ERROR_STOP on

DO $precondition$
BEGIN
  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public' AND table_name IN ('relation','assertion','conclusion')
        AND column_name='id' AND is_identity='YES') <> 3 THEN
    RAISE EXCEPTION 'C3_SEQUENCE_MONOTONIC_REQUIRES_IDENTITY_BASELINE';
  END IF;
END $precondition$;

SET session_replication_role=replica;
INSERT INTO public.change_set(id,operation,summary)
VALUES (-1939512000,'sequence_test','C3 monotonic sequence fixture') ON CONFLICT DO NOTHING;
INSERT INTO public.relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
VALUES (1939512101,'person',-1939512101,'person',-1939512102,'sequence_fixture');
INSERT INTO public.assertion(id,target_type,target_id,vaerdi_tekst,uforanderlig)
VALUES (1939512101,'fact',-1939512191,'sequence fixture',false);
INSERT INTO public.conclusion(id,target_type,target_id,valgt_assertion_id,status)
VALUES (1939512101,'fact',-1939512191,1939512101,'afklaret');
INSERT INTO public.change_event(id,change_set_id,seq,tabel,row_pk,op)
VALUES
  (-1939512101,-1939512000,1,'relation',jsonb_build_object('id',1939512201),'DELETE'),
  (-1939512102,-1939512000,2,'assertion',jsonb_build_object('id',1939512201),'DELETE'),
  (-1939512103,-1939512000,3,'conclusion',jsonb_build_object('id',1939512201),'DELETE');
RESET session_replication_role;

SELECT setval(pg_get_serial_sequence('public.relation','id'),1,false);
SELECT setval(pg_get_serial_sequence('public.assertion','id'),1,false);
SELECT setval(pg_get_serial_sequence('public.conclusion','id'),1,false);
\ir ../../db-migrations-c3-identity.sql

SET session_replication_role=replica;
INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
VALUES ('person',-1939512103,'person',-1939512104,'sequence_history') RETURNING id AS relation_id \gset history_
INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst,uforanderlig)
VALUES ('fact',-1939512192,'sequence history',false) RETURNING id AS assertion_id \gset history_
INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status)
VALUES ('fact',-1939512192,:'history_assertion_id','afklaret') RETURNING id AS conclusion_id \gset history_
RESET session_replication_role;

SELECT 1/CASE WHEN :'history_relation_id'::bigint>1939512201 THEN 1 ELSE 0 END;
SELECT 1/CASE WHEN :'history_assertion_id'::bigint>1939512201 THEN 1 ELSE 0 END;
SELECT 1/CASE WHEN :'history_conclusion_id'::bigint>1939512201 THEN 1 ELSE 0 END;

SELECT setval(pg_get_serial_sequence('public.relation','id'),1939512301,false);
SELECT setval(pg_get_serial_sequence('public.assertion','id'),1939512301,false);
SELECT setval(pg_get_serial_sequence('public.conclusion','id'),1939512301,false);
\ir ../../db-migrations-c3-identity.sql
\ir ../../db-migrations-c3-identity.sql

SET session_replication_role=replica;
INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
VALUES ('person',-1939512105,'person',-1939512106,'sequence_current') RETURNING id AS relation_id \gset current_
INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst,uforanderlig)
VALUES ('fact',-1939512193,'sequence current',false) RETURNING id AS assertion_id \gset current_
INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status)
VALUES ('fact',-1939512193,:'current_assertion_id','afklaret') RETURNING id AS conclusion_id \gset current_
RESET session_replication_role;

SELECT 1/CASE WHEN :'current_relation_id'::bigint>=1939512301 THEN 1 ELSE 0 END;
SELECT 1/CASE WHEN :'current_assertion_id'::bigint>=1939512301 THEN 1 ELSE 0 END;
SELECT 1/CASE WHEN :'current_conclusion_id'::bigint>=1939512301 THEN 1 ELSE 0 END;

DO $success$
BEGIN
  RAISE NOTICE 'OK: C3 sequence floors preserve live, history and current state';
END $success$;
