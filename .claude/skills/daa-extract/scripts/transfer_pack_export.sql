-- Restorens afgørelser til pakken (spec §4.1). Læse-kun. Indeholder evidens med noter:
-- skriv output til en 0600-fil og læs det aldrig — kun tæl. Input: src. Output: daa.pack_export.
-- restore_interpretation_id = version 1-rækkens id (det, arkets `D <id> <version>`-linjer og maskinens
-- plan-/klassifikationsfiler peger på; spec §4.1); restore_decision_interpretation_id = den afgjorte
-- versions id (restorens aktuelle række).
WITH cur AS (
  SELECT ic.* FROM private.interpretation_current ic WHERE ic.source_id = :src AND ic.status <> 'proposed'
), v1 AS (
  SELECT i.id, i.interpretation_key FROM private.interpretation i WHERE i.source_id = :src AND i.version = 1
)
SELECT set_config('daa.pack_export', jsonb_build_object(
  'decisions', coalesce((SELECT jsonb_agg(jsonb_build_object(
      'interpretation_key', cur.interpretation_key, 'restore_interpretation_id', v1.id,
      'restore_decision_interpretation_id', cur.id, 'status', cur.status, 'evidence', cur.decision_evidence,
      'decided_by', cur.decided_by) ORDER BY cur.interpretation_key)
    FROM cur JOIN v1 ON v1.interpretation_key = cur.interpretation_key), '[]'::jsonb),
  'key_by_v1_id', coalesce((SELECT jsonb_object_agg(id::text, interpretation_key::text) FROM v1), '{}'::jsonb)
)::text, false) AS pack_export;
