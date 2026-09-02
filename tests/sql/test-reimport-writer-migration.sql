\set ON_ERROR_STOP on

\if :{?task4_atomicity_expect_rollback}
-- Run after a deliberately late #153 migration failure.  No visible part of
-- the terminal legacy ledger may have crossed the cutover boundary.
DO $atomicity$
BEGIN
  IF (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_authorization'::regclass)<>'r'
     OR (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_write_batch'::regclass)<>'r'
     OR (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_write_event'::regclass)<>'r'
     OR (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_name_completion_result'::regclass)<>'r'
     OR to_regclass('private.reimport_authorization') IS NOT NULL
     OR to_regclass('private.reimport_batch') IS NOT NULL
     OR to_regclass('private.reimport_event') IS NOT NULL
     OR to_regclass('private.reimport_writer_profile') IS NOT NULL
     OR NOT EXISTS(SELECT 1 FROM private.reimport_1939_authorization WHERE id='15300000-0000-4000-8000-000000000101')
     OR NOT EXISTS(SELECT 1 FROM private.reimport_1939_write_batch WHERE id='15300000-0000-4000-8000-000000000102')
     OR NOT EXISTS(SELECT 1 FROM private.reimport_1939_write_event WHERE id=153101) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_MIGRATION_ATOMIC_ROLLBACK_FAILED';
  END IF;
END $atomicity$;
\else

-- Run only after a pre-#153 terminal ledger has been populated, then migrated.
-- The fixture deliberately has no executable legacy work: each authorization
-- is consumed or expired and each batch is reversed or activated.
DO $migration$
BEGIN
  IF (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_authorization'::regclass)<>'v'
     OR (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_write_batch'::regclass)<>'v'
     OR (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_write_event'::regclass)<>'v'
     OR (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_name_completion_result'::regclass)<>'v' THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_MIGRATION_FACADE_REQUIRED';
  END IF;
  IF to_regclass('private.reimport_authorization') IS NULL
     OR to_regclass('private.reimport_batch') IS NULL
     OR to_regclass('private.reimport_event') IS NULL
     OR NOT EXISTS(SELECT 1 FROM private.reimport_authorization WHERE id='15300000-0000-4000-8000-000000000101')
     OR NOT EXISTS(SELECT 1 FROM private.reimport_batch WHERE id='15300000-0000-4000-8000-000000000102')
     OR NOT EXISTS(SELECT 1 FROM private.reimport_event WHERE id=153101)
     OR NOT EXISTS(SELECT 1 FROM private.reimport_name_completion_result WHERE id='15300000-0000-4000-8000-000000000106') THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_MIGRATION_LEDGER_IDENTITY_LOST';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM private.reimport_authorization WHERE id='15300000-0000-4000-8000-000000000101'
                  AND operation='reimport' AND status='consumed' AND manifest_sha256=repeat('a',64)
                  AND preview_sha256=repeat('b',64) AND source_id=3
                  AND profile_id='daa-1939-v50-production-write-v1' AND profile_sha256=repeat('a',64))
     OR NOT EXISTS(SELECT 1 FROM private.reimport_authorization WHERE id='15300000-0000-4000-8000-000000000103'
                    AND operation='cutover' AND status='consumed' AND manifest_sha256=repeat('a',64))
     OR NOT EXISTS(SELECT 1 FROM private.reimport_authorization WHERE id='15300000-0000-4000-8000-000000000104'
                    AND operation='reversal' AND status='expired' AND manifest_sha256=repeat('c',64))
     OR NOT EXISTS(SELECT 1 FROM private.reimport_batch WHERE id='15300000-0000-4000-8000-000000000102'
                    AND authorization_id='15300000-0000-4000-8000-000000000101' AND status='reversed'
                    AND manifest_sha256=repeat('a',64) AND preview_sha256=repeat('b',64)
                    AND source_id=3 AND profile_id='daa-1939-v50-production-write-v1' AND profile_sha256=repeat('a',64))
     OR NOT EXISTS(SELECT 1 FROM private.reimport_batch WHERE id='15300000-0000-4000-8000-000000000105'
                    AND authorization_id='15300000-0000-4000-8000-000000000103' AND status='activated'
                    AND manifest_sha256=repeat('a',64) AND preview_sha256=repeat('b',64))
     OR NOT EXISTS(SELECT 1 FROM private.reimport_event WHERE id=153101
                    AND batch_id='15300000-0000-4000-8000-000000000102'
                    AND element_id='legacy:153:reversal' AND operation='reversal' AND after_sha256=repeat('d',64))
     OR NOT EXISTS(SELECT 1 FROM private.reimport_event WHERE id=153102
                    AND batch_id='15300000-0000-4000-8000-000000000105'
                    AND element_id='legacy:153:activation' AND operation='activation' AND after_sha256=repeat('e',64))
     OR NOT EXISTS(SELECT 1 FROM private.reimport_name_completion_result WHERE id='15300000-0000-4000-8000-000000000106'
                    AND batch_id='15300000-0000-4000-8000-000000000105'
                    AND source_batch_id='15300000-0000-4000-8000-000000000102'
                    AND payload_sha256=repeat('f',64) AND result_sha256=repeat('0',64)) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_MIGRATION_PROFILE_PARITY_FAILED';
  END IF;
  IF has_table_privilege('anon','private.reimport_1939_write_event','SELECT')
     OR has_table_privilege('authenticated','private.reimport_1939_write_event','SELECT') THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_MIGRATION_PRIVATE_ACL_INVALID';
  END IF;
  IF EXISTS(
    SELECT 1
    FROM pg_constraint c
    WHERE c.conrelid IN (
      'private.reimport_authorization'::regclass,
      'private.reimport_batch'::regclass,
      'private.reimport_event'::regclass,
      'private.reimport_name_completion_result'::regclass
    )
      AND c.conname LIKE 'reimport_1939_%'
  ) OR EXISTS(
    SELECT 1
    FROM pg_index x
    JOIN pg_class i ON i.oid=x.indexrelid
    WHERE x.indrelid IN (
      'private.reimport_authorization'::regclass,
      'private.reimport_batch'::regclass,
      'private.reimport_event'::regclass,
      'private.reimport_name_completion_result'::regclass
    )
      AND i.relname LIKE 'reimport_1939_%'
  ) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_MIGRATION_LEGACY_INDEX_IDENTITY_RETAINED';
  END IF;
END $migration$;
\endif
