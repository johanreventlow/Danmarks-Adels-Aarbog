\set ON_ERROR_STOP on

-- Consumes the 2d6aabf-only RPC fixture.  Its marker locates the preserved
-- chain without assuming generated UUID or identity-sequence values.
\if :{?task4_atomicity_expect_rollback}
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
     OR NOT EXISTS(
       SELECT 1
       FROM private.reimport_1939_write_batch source_batch
       JOIN private.reimport_1939_authorization source_authorization
         ON source_authorization.id=source_batch.authorization_id
       JOIN private.reimport_1939_write_event source_event
         ON source_event.batch_id=source_batch.id
       JOIN private.reimport_1939_write_batch completion_batch
         ON completion_batch.status='finalized'
       JOIN private.reimport_1939_authorization completion_authorization
         ON completion_authorization.id=completion_batch.authorization_id
       JOIN private.reimport_1939_name_completion_result completion_result
         ON completion_result.batch_id=completion_batch.id
        AND completion_result.source_batch_id=source_batch.id
       WHERE source_authorization.operation='reimport'
         AND source_authorization.status='consumed'
         AND source_batch.status='activated'
         AND completion_authorization.operation='name_completion'
         AND completion_authorization.status='consumed'
         AND source_event.operation='person_create'
         AND source_event.source_record_key LIKE 'legacy-terminal-rpc-153-%'
       GROUP BY source_batch.id,completion_batch.id
       HAVING count(DISTINCT source_event.id)=8
          AND count(DISTINCT completion_result.id)=8
          AND (SELECT count(*) FROM private.reimport_1939_write_event completion_event
                 WHERE completion_event.batch_id=completion_batch.id
                   AND completion_event.operation='canonical_delta')=8
     )
     OR NOT EXISTS(
       SELECT 1
       FROM private.reimport_1939_write_batch source_batch
       JOIN private.reimport_1939_authorization source_authorization
         ON source_authorization.id=source_batch.authorization_id
       JOIN private.reimport_1939_write_batch completion_batch
         ON completion_batch.status='reversed'
       JOIN private.reimport_1939_authorization completion_authorization
         ON completion_authorization.id=completion_batch.authorization_id
       WHERE source_authorization.operation='reimport'
         AND source_authorization.status='consumed'
         AND source_batch.status='reversed'
         AND completion_authorization.operation='name_completion'
         AND completion_authorization.status='consumed'
         AND completion_authorization.authorized_elements->'payloads' @> jsonb_build_object(
           'name-completion:legacy-terminal-rpc-153-reversed-1',
           jsonb_build_object('source_batch_id',source_batch.id::text)
         )
         AND (SELECT count(*) FROM private.reimport_1939_name_completion_result completion_result
               WHERE completion_result.batch_id=completion_batch.id
                 AND completion_result.source_batch_id=source_batch.id)=8
         AND (SELECT count(*) FROM private.reimport_1939_write_event completion_event
               WHERE completion_event.batch_id=completion_batch.id
                 AND completion_event.operation='canonical_delta')=8
     ) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_MIGRATION_ATOMIC_ROLLBACK_FAILED';
  END IF;
END $atomicity$;
\else
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
     OR to_regclass('private.reimport_name_completion_result') IS NULL THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_MIGRATION_LEDGER_IDENTITY_LOST';
  END IF;
  IF NOT EXISTS(
       SELECT 1 FROM private.reimport_writer_profile
        WHERE source_id=3 AND profile_id='daa-1939-v50-production-write-v1'
          AND profile_sha256=private.reimport_canonical_json_sha256(writer_config)
     ) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_MIGRATION_PROFILE_HASH_INVALID';
  END IF;
  IF to_regprocedure('private.validate_reimport_writer_config(jsonb)') IS NULL
     OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='private.reimport_writer_profile'::regclass AND conname='reimport_writer_profile_config_valid') THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_MIGRATION_PROFILE_CONFIG_CONTRACT_MISSING';
  END IF;
  IF NOT EXISTS(
    SELECT 1
    FROM private.reimport_batch source_batch
    JOIN private.reimport_authorization source_authorization
      ON source_authorization.id=source_batch.authorization_id
    JOIN private.reimport_event source_event
      ON source_event.batch_id=source_batch.id
    JOIN private.reimport_batch completion_batch
      ON completion_batch.status='finalized'
    JOIN private.reimport_authorization completion_authorization
      ON completion_authorization.id=completion_batch.authorization_id
    JOIN private.reimport_name_completion_result completion_result
      ON completion_result.batch_id=completion_batch.id
     AND completion_result.source_batch_id=source_batch.id
    WHERE source_authorization.operation='reimport'
      AND source_authorization.status='consumed'
      AND source_authorization.source_id=3
      AND source_authorization.profile_id='daa-1939-v50-production-write-v1'
      AND source_authorization.profile_sha256=(SELECT profile_sha256 FROM private.reimport_writer_profile WHERE source_id=3 AND profile_id='daa-1939-v50-production-write-v1')
      AND source_batch.status='activated'
      AND source_batch.source_id=3
      AND source_batch.profile_id='daa-1939-v50-production-write-v1'
      AND source_batch.profile_sha256=source_authorization.profile_sha256
      AND source_batch.expected_counts='{"person_creates":8,"source_evidence":0,"canonical_delta":0}'::jsonb
      AND source_batch.observed_counts=source_batch.expected_counts
      AND completion_authorization.operation='name_completion'
      AND completion_authorization.status='consumed'
      AND completion_authorization.source_id=source_batch.source_id
      AND completion_authorization.profile_id=source_batch.profile_id
      AND completion_authorization.profile_sha256=source_batch.profile_sha256
      AND completion_batch.source_id=source_batch.source_id
      AND completion_batch.profile_id=source_batch.profile_id
      AND completion_batch.profile_sha256=source_batch.profile_sha256
      AND completion_batch.expected_counts='{"name_completions":8,"operations":8}'::jsonb
      AND completion_batch.observed_counts=completion_batch.expected_counts
      AND source_event.operation='person_create'
      AND source_event.source_record_key LIKE 'legacy-terminal-rpc-153-%'
    GROUP BY source_batch.id,completion_batch.id
    HAVING count(DISTINCT source_event.id)=8
       AND count(DISTINCT completion_result.id)=8
       AND count(DISTINCT completion_result.person_id)=8
       AND count(DISTINCT completion_result.fact_id)=8
       AND count(DISTINCT completion_result.assertion_id)=8
       AND count(DISTINCT completion_result.citation_id)=8
       AND count(DISTINCT completion_result.conclusion_id)=8
       AND (SELECT count(*) FROM private.reimport_event completion_event
              WHERE completion_event.batch_id=completion_batch.id
                AND completion_event.operation='canonical_delta')=8
  ) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_MIGRATION_RPC_TERMINAL_CHAIN_LOST';
  END IF;
  -- The historical fixture deliberately supplies both terminal forms.  Keep
  -- them distinct here: both preserve their child event/result ledger, but
  -- only the first remains activated while the second is reversed by the old
  -- RPC lifecycle.
  IF NOT EXISTS(
    SELECT 1
    FROM private.reimport_batch source_batch
    JOIN private.reimport_authorization source_authorization
      ON source_authorization.id=source_batch.authorization_id
    JOIN private.reimport_batch completion_batch
      ON completion_batch.status='finalized'
    JOIN private.reimport_authorization completion_authorization
      ON completion_authorization.id=completion_batch.authorization_id
    WHERE source_authorization.operation='reimport'
      AND source_batch.status='activated'
      AND EXISTS(
        SELECT 1 FROM private.reimport_event source_event
         WHERE source_event.batch_id=source_batch.id
           AND source_event.operation='person_create'
           AND source_event.source_record_key LIKE 'legacy-terminal-rpc-153-%'
           AND source_event.source_record_key NOT LIKE 'legacy-terminal-rpc-153-reversed-%'
      )
      AND completion_authorization.operation='name_completion'
      AND completion_authorization.authorized_elements->'payloads' @> jsonb_build_object(
        'name-completion:legacy-terminal-rpc-153-1',
        jsonb_build_object('source_batch_id',source_batch.id::text)
      )
      AND (SELECT count(*) FROM private.reimport_name_completion_result result
            WHERE result.batch_id=completion_batch.id
              AND result.source_batch_id=source_batch.id)=8
  ) OR NOT EXISTS(
    SELECT 1
    FROM private.reimport_batch source_batch
    JOIN private.reimport_authorization source_authorization
      ON source_authorization.id=source_batch.authorization_id
    JOIN private.reimport_batch completion_batch
      ON completion_batch.status='reversed'
    JOIN private.reimport_authorization completion_authorization
      ON completion_authorization.id=completion_batch.authorization_id
    WHERE source_authorization.operation='reimport'
      AND source_batch.status='reversed'
      AND EXISTS(
        SELECT 1 FROM private.reimport_event source_event
         WHERE source_event.batch_id=source_batch.id
           AND source_event.operation='person_create'
           AND source_event.source_record_key LIKE 'legacy-terminal-rpc-153-reversed-%'
      )
      AND completion_authorization.operation='name_completion'
      AND completion_authorization.authorized_elements->'payloads' @> jsonb_build_object(
        'name-completion:legacy-terminal-rpc-153-reversed-1',
        jsonb_build_object('source_batch_id',source_batch.id::text)
      )
      AND (SELECT count(*) FROM private.reimport_name_completion_result result
            WHERE result.batch_id=completion_batch.id
              AND result.source_batch_id=source_batch.id)=8
      AND (SELECT count(*) FROM private.reimport_event completion_event
            WHERE completion_event.batch_id=completion_batch.id
              AND completion_event.operation='canonical_delta')=8
  ) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_MIGRATION_TERMINAL_TOPOLOGY_LOST';
  END IF;
  IF has_table_privilege('anon','private.reimport_1939_write_event','SELECT')
     OR has_table_privilege('authenticated','private.reimport_1939_write_event','SELECT') THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_MIGRATION_PRIVATE_ACL_INVALID';
  END IF;
  IF to_regprocedure('public.red_reimport_batch_result(uuid,uuid)') IS NULL
     OR has_function_privilege('anon','public.red_reimport_batch_result(uuid,uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.red_reimport_batch_result(uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_reimport_batch_result(uuid,uuid)','EXECUTE')
     OR has_table_privilege('authenticated','private.reimport_authorization','SELECT')
     OR has_table_privilege('authenticated','private.reimport_batch','SELECT')
     OR has_table_privilege('authenticated','private.reimport_event','SELECT') THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_MIGRATION_RESULT_ACL_INVALID';
  END IF;
  IF EXISTS(
    SELECT 1 FROM pg_constraint c
    WHERE c.conrelid IN (
      'private.reimport_authorization'::regclass,
      'private.reimport_batch'::regclass,
      'private.reimport_event'::regclass,
      'private.reimport_name_completion_result'::regclass
    ) AND c.conname LIKE 'reimport_1939_%'
  ) OR EXISTS(
    SELECT 1 FROM pg_index x JOIN pg_class i ON i.oid=x.indexrelid
    WHERE x.indrelid IN (
      'private.reimport_authorization'::regclass,
      'private.reimport_batch'::regclass,
      'private.reimport_event'::regclass,
      'private.reimport_name_completion_result'::regclass
    ) AND i.relname LIKE 'reimport_1939_%'
  ) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_MIGRATION_LEGACY_INDEX_IDENTITY_RETAINED';
  END IF;
END $migration$;
\endif
