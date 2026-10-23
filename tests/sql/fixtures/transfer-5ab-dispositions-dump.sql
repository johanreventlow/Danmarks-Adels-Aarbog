-- 5a+5b-overførslen, plan B1 (Task 2/3a): dumpets side af dispositionsleddet. Én maskinel disposition
-- afventer_identitet på klausulen med Bo Betas ægteskab i kilde -25001, så relation_disposition_input har ét element,
-- når kæden har afgjort Bo Beta (målt i review runde 2: relation_dispositions = 1). Køres som ejer efter
-- indholds-id-dump.sql i dumpets transaktion; B får rækken via kopien. Evidensen er som 4.1c's (manifest-hash og en
-- udtrækskørsel, der findes i dumpet).
INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence)
SELECT io.observation_id,1,'afventer_identitet','machine',
       jsonb_build_object('manifest_sha256',repeat('e',64),'extraction_run_id',i.extraction_run_id)
  FROM private.interpretation i
  JOIN private.interpretation_observation io ON io.interpretation_id=i.id AND io.ordinal=1
 WHERE i.source_id=-25001 AND i.predicate='relation.marriage' AND i.value->>'raw' LIKE '%Bo Beta%'
   AND i.extraction_run_id IS NOT NULL;
DO $$ BEGIN
  IF (SELECT count(*) FROM private.clause_disposition) <> 1 THEN RAISE EXCEPTION 'T5_FIXTURE: ikke én disposition'; END IF;
END $$;
