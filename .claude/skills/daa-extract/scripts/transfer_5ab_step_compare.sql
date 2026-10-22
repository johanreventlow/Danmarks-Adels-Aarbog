-- Fælles: i replay skal basens items være lig pakkens, ellers stopper skridtet før RPC'en. Inkluderes med \ir.
\if :t5_replay
DO $c$ BEGIN
  IF current_setting('daa.t5_items')::jsonb IS DISTINCT FROM current_setting('daa.t5_pack_items')::jsonb THEN
    RAISE EXCEPTION 'STEP_ITEMS_MISMATCH %', current_setting('daa.t5_step');
  END IF;
END $c$;
\endif
