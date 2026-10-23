-- Fælles udgang: fejlkrogen (kun test) lige før COMMIT, derefter én linje STEP_OK. Inkluderes med \ir.
\if :{?fault}
SELECT :'fault'='before_commit' AS t5_fault_bc \gset
\if :t5_fault_bc
DO $$ BEGIN RAISE EXCEPTION 'STEP_FAULT before_commit'; END $$;
\endif
\endif
COMMIT;
\if :t5_replay
\else
\set t5_mv `/bin/mv -- :'t5_items_tmp' :'items' && echo ok`
SELECT :'t5_mv'='ok' AS t5_mv_ok \gset
\if :t5_mv_ok
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_ITEMS_RENAME'; END $$;
\endif
\endif
\echo STEP_OK :t5_step n=:t5_n:t5_extra items_sha256=:t5_sha
