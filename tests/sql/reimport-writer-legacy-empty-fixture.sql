\set ON_ERROR_STOP on

-- A pre-#153 installation may have created the physical v1 ledger without
-- ever authorizing a run.  Retain source 3 for the later v2 profile bootstrap,
-- but leave every old journal relation genuinely empty.
INSERT INTO public.source(id,titel,udgave,slags)
VALUES (3,'DAA','1939','DAA-udgave')
ON CONFLICT (id) DO NOTHING;

DO $fixture$
BEGIN
  IF (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_authorization'::regclass)<>'r'
     OR (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_write_batch'::regclass)<>'r'
     OR (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_write_event'::regclass)<>'r'
     OR (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_name_completion_result'::regclass)<>'r'
     OR EXISTS(SELECT 1 FROM private.reimport_1939_authorization)
     OR EXISTS(SELECT 1 FROM private.reimport_1939_write_batch)
     OR EXISTS(SELECT 1 FROM private.reimport_1939_write_event)
     OR EXISTS(SELECT 1 FROM private.reimport_1939_name_completion_result) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_LEGACY_EMPTY_FIXTURE_INVALID';
  END IF;
END $fixture$;
