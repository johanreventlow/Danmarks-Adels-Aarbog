-- 5a+5b-overførslen, plan B1 Task 3b: kædens side af del 1 oven på transfer-5ab-del1-dump.sql. Ægtefællepersonas gennem
-- den rigtige writer (én pr. ægteskabspåstand, som indholds-id-chain.sql trin 1), men ingen kandidatkørsler og ingen
-- kontrolkørsel: dem laver skridtene. Køres som ejer efter relation-5b.sql i harnessets transaktion og afslutter med COMMIT.
DO $chain$
DECLARE v_el jsonb;
BEGIN
  SELECT jsonb_object_agg('relation-persona:'||ic.interpretation_key::text,
           pg_temp.f5b_payload(NULL,jsonb_build_object('key',ic.interpretation_key),io.observation_id,ic.value->>'raw',
             substring(ic.value->>'raw' from '^g[.] m[.] (.+)[.]$')))
    INTO v_el
    FROM private.interpretation_current ic
    JOIN private.interpretation_observation io ON io.interpretation_id=ic.id AND io.ordinal=1
   WHERE ic.source_id=-25101 AND ic.predicate='relation.marriage';
  PERFORM pg_temp.f5b_write(-25101,'11000000-0000-0000-0000-000000025001',v_el);
END $chain$;
COMMIT;
