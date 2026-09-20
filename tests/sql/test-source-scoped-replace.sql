-- #153 Task 4.  Run only after bootstrap and schema.sql on a fresh disposable DB.
BEGIN;

DO $source_scoped_replace_red$
BEGIN
  IF to_regclass('private.source_scoped_replace_authorization') IS NULL
     OR to_regclass('private.source_scoped_replace_batch') IS NULL
     OR to_regclass('private.source_scoped_replace_event') IS NULL THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_LEDGER_MISSING';
  END IF;
  IF to_regprocedure('public.red_authorize_source_scoped_replace(text,text,uuid,uuid,jsonb,text,text,timestamptz)') IS NULL
     OR to_regprocedure('public.red_apply_source_scoped_replace(uuid,jsonb)') IS NULL
     OR to_regprocedure('public.red_verify_source_scoped_replace(uuid)') IS NULL THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_REPLACE_RPC_MISSING';
  END IF;
END
$source_scoped_replace_red$;

ROLLBACK;
