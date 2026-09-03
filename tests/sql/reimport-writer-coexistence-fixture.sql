\set ON_ERROR_STOP on

-- Build the terminal v1 chain through the pinned pre-#153 public API, then
-- add the empty generic shells which an interrupted older upgrade could have
-- left beside it.  This is disposable migration evidence, never production
-- DDL or an alternate writer shape.
\ir reimport-writer-legacy-terminal-fixture.sql

CREATE TABLE private.reimport_authorization
  (LIKE private.reimport_1939_authorization INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
ALTER TABLE private.reimport_authorization
  ADD PRIMARY KEY(id), ADD UNIQUE(nonce),
  ADD FOREIGN KEY(source_id) REFERENCES public.source(id);

CREATE TABLE private.reimport_batch
  (LIKE private.reimport_1939_write_batch INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
ALTER TABLE private.reimport_batch
  ADD PRIMARY KEY(id), ADD UNIQUE(authorization_id),
  ADD FOREIGN KEY(authorization_id) REFERENCES private.reimport_authorization(id);

CREATE TABLE private.reimport_event
  (LIKE private.reimport_1939_write_event INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING IDENTITY);
ALTER TABLE private.reimport_event
  ADD PRIMARY KEY(id), ADD UNIQUE(batch_id,element_id),
  ADD FOREIGN KEY(batch_id) REFERENCES private.reimport_batch(id);

CREATE TABLE private.reimport_name_completion_result
  (LIKE private.reimport_1939_name_completion_result INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
ALTER TABLE private.reimport_name_completion_result
  ADD PRIMARY KEY(id), ADD UNIQUE(batch_id,element_id),
  ADD UNIQUE(source_batch_id,person_id,source_record_id),
  ADD FOREIGN KEY(batch_id) REFERENCES private.reimport_batch(id),
  ADD FOREIGN KEY(source_batch_id) REFERENCES private.reimport_batch(id);

DO $fixture$
DECLARE
  v_relation text;
  v_constraint record;
  v_constraint_name text;
BEGIN
  -- LIKE preserves check-constraint names from the legacy source tables.
  -- A genuine generic shell already has generic catalog identities, so rename
  -- the copied checks before the rollback snapshot is frozen.
  FOR v_constraint IN
    SELECT conrelid,conname
      FROM pg_constraint
     WHERE conrelid IN (
       'private.reimport_authorization'::regclass,
       'private.reimport_batch'::regclass,
       'private.reimport_event'::regclass,
       'private.reimport_name_completion_result'::regclass
     ) AND conname LIKE 'reimport_1939_%'
  LOOP
    v_constraint_name:=CASE
      WHEN v_constraint.conname LIKE 'reimport_1939_write_batch_%'
        THEN replace(v_constraint.conname,'reimport_1939_write_batch_','reimport_batch_')
      WHEN v_constraint.conname LIKE 'reimport_1939_write_event_%'
        THEN replace(v_constraint.conname,'reimport_1939_write_event_','reimport_event_')
      ELSE replace(v_constraint.conname,'reimport_1939_','reimport_')
    END;
    EXECUTE format('ALTER TABLE %s RENAME CONSTRAINT %I TO %I',
      v_constraint.conrelid::regclass,v_constraint.conname,left(v_constraint_name,63));
  END LOOP;

  IF to_regclass('private.reimport_event_id_seq') IS NULL THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_COEXISTENCE_SEQUENCE_MISSING';
  END IF;
  ALTER SEQUENCE private.reimport_event_id_seq RESTART WITH 509;

  CREATE TABLE private.reimport_writer_coexistence_snapshot (
    relation_name text PRIMARY KEY,
    relation_oid oid NOT NULL,
    relfilenode oid NOT NULL,
    relkind "char" NOT NULL,
    contents_sha256 text NOT NULL,
    sequence_oid oid NOT NULL,
    sequence_last_value bigint NOT NULL,
    sequence_is_called boolean NOT NULL
  );

  FOREACH v_relation IN ARRAY ARRAY[
    'private.reimport_1939_authorization',
    'private.reimport_1939_write_batch',
    'private.reimport_1939_write_event',
    'private.reimport_1939_name_completion_result',
    'private.reimport_authorization',
    'private.reimport_batch',
    'private.reimport_event',
    'private.reimport_name_completion_result'
  ] LOOP
    EXECUTE format($snapshot$
      INSERT INTO private.reimport_writer_coexistence_snapshot(
        relation_name,relation_oid,relfilenode,relkind,contents_sha256,
        sequence_oid,sequence_last_value,sequence_is_called
      )
      SELECT %L,c.oid,c.relfilenode,c.relkind,
             (SELECT encode(extensions.digest(convert_to(
                coalesce(string_agg(row_to_json(row_value)::text,E'\\n' ORDER BY row_value.id::text),''),
                'UTF8'),'sha256'),'hex') FROM %s row_value),
             'private.reimport_event_id_seq'::regclass,
             sequence_state.last_value,sequence_state.is_called
        FROM pg_class c
        CROSS JOIN private.reimport_event_id_seq sequence_state
       WHERE c.oid=%L::regclass
    $snapshot$,v_relation,v_relation,v_relation);
  END LOOP;
END $fixture$;
