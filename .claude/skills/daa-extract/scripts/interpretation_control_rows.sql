-- Rækkefilen til afgørelsesarket: hvert `proposed` forslag med postens nøgle, værdi og de
-- citerede klausuler (plan 4.5 Task 5 Step 5, ordret; plan 2026-09-27 Task 2). Læse-kun.
-- Output indeholder klausultekst: skriv det til en 0600-fil, og læs det aldrig — kun tæl.
-- `value_text`: strengen selv, eller `raw` for objekter (4.3b-arkets regel).
WITH rows AS (
  SELECT ic.id AS interpretation_id, ic.version, sr.record_key, ic.predicate,
         CASE jsonb_typeof(ic.value) WHEN 'string' THEN ic.value #>> '{}' ELSE ic.value->>'raw' END AS value_text,
         ic.confidence, CASE WHEN ic.source_persona_id IS NULL THEN 'other' ELSE 'principal' END AS persona_role,
         jsonb_agg(jsonb_build_object('ordinal', so.clause_ordinal, 'text', so.verbatim_text,
                   'flags', coalesce(so.clause_flags, '[]'::jsonb)) ORDER BY so.clause_ordinal) AS cited
    FROM private.interpretation_current ic
    JOIN private.interpretation_observation io ON io.interpretation_id = ic.id
    JOIN private.source_observation so ON so.id = io.observation_id
    JOIN private.source_record_anchor_current ac ON ac.occurrence_id = so.occurrence_id
                                               AND ac.decision_status = 'accepted'
    JOIN private.source_record sr ON sr.id = ac.source_record_id
   WHERE ic.status = 'proposed'
   GROUP BY ic.id, ic.version, sr.record_key, ic.predicate, ic.value, ic.confidence, ic.source_persona_id)
SELECT coalesce(jsonb_agg(to_jsonb(rows) ORDER BY record_key, predicate, interpretation_id), '[]') FROM rows;
