\set ON_ERROR_STOP on

-- Disposable-database runner for the complete canonical db-verify.sql suite.
-- db-verify contains legacy integration checks that intentionally operate on
-- one existing person/source and a fixed synthetic redaction subject. Provide
-- only those exact prerequisites here; individual feature fixtures stay in
-- db-verify and this runner removes its prerequisites after a green run.
-- Never run this wrapper against production.

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions;
SET search_path TO public, private, extensions, pg_catalog;

DO $dblink_required$
BEGIN
  IF to_regprocedure('dblink_connect(text,text)') IS NULL THEN
    RAISE EXCEPTION 'DB_VERIFY_DBLINK_REQUIRED: disposable runner';
  END IF;
END $dblink_required$;

SELECT set_config('daa.verify_dblink_evidence_anchor','pending',false);
SELECT set_config('daa.verify_dblink_revision_anchor','pending',false);
SELECT set_config('daa.verify_dblink_promotion','pending',false);
SELECT set_config('daa.verify_dblink_interpretation','pending',false);
SELECT set_config('daa.verify_dblink_identity','pending',false);
SELECT set_config('daa.verify_dblink_placement','pending',false);
SELECT set_config('daa.verify_dblink_ocr_lock','pending',false);

DELETE FROM lineage WHERE id IN (-987659904,-987659903);
DELETE FROM source WHERE id=-987659902;
DELETE FROM person WHERE id=-987659901;
DELETE FROM profiles WHERE id='00000000-0000-0000-0000-000000000001';
DELETE FROM auth.users WHERE id='00000000-0000-0000-0000-000000000001';

INSERT INTO auth.users(id,email)
VALUES ('00000000-0000-0000-0000-000000000001',
        'db-verify-runner@example.invalid');
INSERT INTO profiles(id,rolle,email)
VALUES ('00000000-0000-0000-0000-000000000001',
        'redaktion','db-verify-runner@example.invalid');
INSERT INTO person(id,levende,privat,status)
VALUES (-987659901,false,false,'db-verify synthetic prerequisite');
INSERT INTO source(id,slags,titel,import_key)
VALUES (-987659902,'test','db-verify synthetic prerequisite',
        'db-verify-synthetic-prerequisite');
INSERT INTO lineage(id,source_id,kode,navn,slaegtsnavn,parent_lineage_id) VALUES
  (-987659903,NULL,NULL,'db-verify synthetic family root','Verify-slægt',NULL),
  (-987659904,-987659902,'I','db-verify synthetic branch',NULL,-987659903);

CREATE TEMP TABLE task3_db_verify_seeded_vocab(code text PRIMARY KEY);
WITH inserted AS (
  INSERT INTO vocab(scheme,code,label) VALUES
    ('faktatype','fødsel','Fødsel'),
    ('faktatype','dåb','Dåb'),
    ('faktatype','død','Død'),
    ('faktatype','begravelse','Begravelse'),
    ('faktatype','floruit','Floruit'),
    ('faktatype','naturalisering','Naturalisation'),
    ('faktatype','introduktion_ridderhus','Introduktion på ridderhus')
  ON CONFLICT (scheme,code) DO NOTHING
  RETURNING code
)
INSERT INTO task3_db_verify_seeded_vocab(code)
SELECT code FROM inserted;

-- Task 6 needs the generic writer's local v2 contract fixture before the
-- historical verifier checks the approved 1939 transition facade.  The
-- bootstrap creates only disposable fixture state and removes its own shims.
BEGIN;
\ir reimport-writer-v2-bootstrap.sql
COMMIT;

\ir ../../db-verify.sql

DO $all_dblink_gates_executed$
DECLARE
  v_missing text[];
BEGIN
  SELECT array_agg(gate ORDER BY gate) INTO v_missing
  FROM (VALUES
    ('evidence_anchor',current_setting('daa.verify_dblink_evidence_anchor',true)),
    ('revision_anchor',current_setting('daa.verify_dblink_revision_anchor',true)),
    ('promotion',current_setting('daa.verify_dblink_promotion',true)),
    ('interpretation',current_setting('daa.verify_dblink_interpretation',true)),
    ('identity',current_setting('daa.verify_dblink_identity',true)),
    ('placement',current_setting('daa.verify_dblink_placement',true)),
    ('ocr_lock',current_setting('daa.verify_dblink_ocr_lock',true))
  ) AS gates(gate,state)
  WHERE state IS DISTINCT FROM 'executed';
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'DB_VERIFY_DBLINK_GATES_NOT_EXECUTED: %',v_missing;
  END IF;
  RAISE NOTICE 'OK: all seven dblink concurrency gates executed';
END $all_dblink_gates_executed$;

DELETE FROM vocab v
USING task3_db_verify_seeded_vocab s
WHERE v.scheme='faktatype' AND v.code=s.code;
DELETE FROM lineage WHERE id IN (-987659904,-987659903);
DELETE FROM source WHERE id=-987659902;
DELETE FROM person WHERE id=-987659901;
DELETE FROM profiles WHERE id='00000000-0000-0000-0000-000000000001';
DELETE FROM auth.users WHERE id='00000000-0000-0000-0000-000000000001';

DO $$ BEGIN
  RAISE NOTICE 'OK: full db-verify.sql completed with disposable prerequisites removed';
END $$;
