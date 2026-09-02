\set ON_ERROR_STOP on

-- #153 Task 6: the edition-named transition surface is a closed catalog.
-- Run after tests/sql/run-db-verify-disposable.sql on a disposable database.

BEGIN;

CREATE FUNCTION pg_temp.task6_expect_catalog_drift(p_label text)
RETURNS void
LANGUAGE plpgsql
AS $task6_expect_catalog_drift$
DECLARE v_error text;
BEGIN
  BEGIN
    PERFORM private.assert_reimport_edition_catalog();
  EXCEPTION WHEN OTHERS THEN
    v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'REIMPORT_EDITION_OBJECT_ALLOWLIST_DRIFT' THEN
    RAISE EXCEPTION 'REIMPORT_EDITION_CATALOG_%_NOT_REJECTED: %',p_label,v_error;
  END IF;
END
$task6_expect_catalog_drift$;

-- The clean, current catalog is the approved baseline.
SELECT private.assert_reimport_edition_catalog();

SAVEPOINT task6_extra_function;
CREATE FUNCTION private.task6_extra_function_1939()
RETURNS void LANGUAGE sql AS 'SELECT NULL::void';
SELECT pg_temp.task6_expect_catalog_drift('FUNCTION');
ROLLBACK TO SAVEPOINT task6_extra_function;

SAVEPOINT task6_extra_relation;
CREATE TABLE private.task6_extra_relation_1939(id bigint);
SELECT pg_temp.task6_expect_catalog_drift('RELATION');
ROLLBACK TO SAVEPOINT task6_extra_relation;

CREATE TABLE private.task6_parent(id bigint PRIMARY KEY);

SAVEPOINT task6_extra_type;
CREATE TYPE private.task6_extra_type_1939 AS ENUM ('task6');
SELECT pg_temp.task6_expect_catalog_drift('TYPE');
ROLLBACK TO SAVEPOINT task6_extra_type;

SAVEPOINT task6_extra_constraint;
ALTER TABLE private.task6_parent
  ADD CONSTRAINT task6_extra_constraint_1939 CHECK (id > 0);
SELECT pg_temp.task6_expect_catalog_drift('CONSTRAINT');
ROLLBACK TO SAVEPOINT task6_extra_constraint;

SAVEPOINT task6_extra_policy;
ALTER TABLE private.task6_parent ENABLE ROW LEVEL SECURITY;
CREATE POLICY task6_extra_policy_1939 ON private.task6_parent FOR SELECT USING (true);
SELECT pg_temp.task6_expect_catalog_drift('POLICY');
ROLLBACK TO SAVEPOINT task6_extra_policy;

SAVEPOINT task6_extra_sequence;
CREATE SEQUENCE private.task6_extra_sequence_1939 OWNED BY private.task6_parent.id;
SELECT pg_temp.task6_expect_catalog_drift('OWNED_SEQUENCE');
ROLLBACK TO SAVEPOINT task6_extra_sequence;

SAVEPOINT task6_extra_index;
CREATE INDEX task6_extra_index_1939 ON private.task6_parent(id);
SELECT pg_temp.task6_expect_catalog_drift('INDEX');
ROLLBACK TO SAVEPOINT task6_extra_index;

CREATE FUNCTION pg_temp.task6_trigger_target()
RETURNS trigger LANGUAGE plpgsql AS $task6_trigger_target$
BEGIN
  RETURN NEW;
END
$task6_trigger_target$;

SAVEPOINT task6_extra_trigger;
CREATE TRIGGER task6_extra_trigger_1939
  BEFORE INSERT ON private.task6_parent
  FOR EACH ROW EXECUTE FUNCTION pg_temp.task6_trigger_target();
SELECT pg_temp.task6_expect_catalog_drift('TRIGGER');
ROLLBACK TO SAVEPOINT task6_extra_trigger;

SELECT private.assert_reimport_edition_catalog();
ROLLBACK;
