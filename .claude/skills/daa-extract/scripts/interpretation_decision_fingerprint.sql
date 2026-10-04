-- Fingeraftryk pr. interpretation_key (spec 2026-10-03 §4.2; 24/9-spec §4.2). Læse-kun.
-- Binder afgørelsen til den tekst, mennesket læste: post, prædikat, værdi og de citerede
-- klausulers (ordinal, tekst-hash), sorteret efter linkets ordinal. Id'er indgår ikke.
-- Input: psql-variablen src. Output: daa.fingerprints = {"<nøgle>": "<sha256>", …} og
-- daa.fingerprint_record_check = {"n_no_record": n, "n_multi_record": n}.
WITH v1 AS (
  SELECT i.id, i.interpretation_key, i.predicate,
         private.interpretation_proposal_canonical_json_sha256(i.value) AS value_sha256
    FROM private.interpretation i
   WHERE i.source_id = :src AND i.version = 1
), rec AS (
  -- Accepteret(e) ankrede post(er) pr. forslag. Fingeraftrykket bruger den C-mindste nøgle;
  -- fingerprint_record_check melder, hvis der ingen eller flere er.
  SELECT v1.id, min(sr.record_key COLLATE "C") AS record_key, count(DISTINCT sr.record_key) AS n_rec
    FROM v1
    JOIN private.interpretation_observation io ON io.interpretation_id = v1.id
    JOIN private.source_observation so ON so.id = io.observation_id
    JOIN private.source_record_anchor_current ac ON ac.occurrence_id = so.occurrence_id
                                               AND ac.decision_status = 'accepted'
    JOIN private.source_record sr ON sr.id = ac.source_record_id
   GROUP BY v1.id
), cl AS (
  SELECT io.interpretation_id AS id,
         jsonb_agg(jsonb_build_array(so.clause_ordinal,
                     encode(extensions.digest(convert_to(so.verbatim_text,'UTF8'),'sha256'),'hex'))
                   ORDER BY io.ordinal) AS clauses
    FROM private.interpretation_observation io
    JOIN private.source_observation so ON so.id = io.observation_id
   WHERE io.interpretation_id IN (SELECT id FROM v1)
   GROUP BY io.interpretation_id
), fp AS (
  SELECT v1.interpretation_key::text AS k,
         encode(extensions.digest(convert_to(private.interpretation_proposal_canonical_json_text(
           jsonb_build_object('fp_version', 1, 'interpretation_key', v1.interpretation_key,
                              'record_key', rec.record_key, 'predicate', v1.predicate,
                              'value_sha256', v1.value_sha256,
                              'clauses', coalesce(cl.clauses, '[]'::jsonb))),'UTF8'),'sha256'),'hex') AS fp
    FROM v1 LEFT JOIN rec USING (id) LEFT JOIN cl USING (id)
)
SELECT set_config('daa.fingerprints', coalesce((SELECT jsonb_object_agg(k, fp) FROM fp), '{}'::jsonb)::text, false)
       AS fingerprints,
       -- Task 4 afviser en pakke, hvis et af tallene er > 0.
       set_config('daa.fingerprint_record_check', jsonb_build_object(
         'n_no_record',    (SELECT count(*) FROM v1 LEFT JOIN rec USING (id) WHERE rec.id IS NULL),
         'n_multi_record', (SELECT count(*) FROM rec WHERE n_rec > 1))::text, false)
       AS record_check;
