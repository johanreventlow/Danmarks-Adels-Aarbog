-- Fælles udgang: fejlkrogen (kun test) lige før COMMIT, derefter én linje STEP_OK. Inkluderes med \ir.
\if :{?fault}
SELECT :'fault'='before_commit' AS t5_fault_bc \gset
\if :t5_fault_bc
DO $$ BEGIN RAISE EXCEPTION 'STEP_FAULT before_commit'; END $$;
\endif
\endif
COMMIT;
\echo STEP_OK :t5_step n=:t5_n:t5_extra items_sha256=:t5_sha
