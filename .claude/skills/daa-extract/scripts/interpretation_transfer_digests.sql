-- Overførslens tre nøglede digests (spec 2026-10-03 §5). Læse-kun; samme bytes i restore,
-- rehearsal og prod. Hver hashet række indeholder interpretation_key; ingen id'er, tidsstempler
-- eller batch-/kørsels-id'er. Input: psql-variablen src. Output: daa.transfer_digests.
WITH v1 AS (
  SELECT i.* FROM private.interpretation i WHERE i.source_id = :src AND i.version = 1
), links AS (
  SELECT io.interpretation_id AS id,
         jsonb_agg(jsonb_build_object(
           'ordinal', io.ordinal, 'clause_ordinal', so.clause_ordinal, 'evidence_role', io.evidence_role,
           'verbatim_sha256', encode(extensions.digest(convert_to(so.verbatim_text,'UTF8'),'sha256'),'hex'),
           'disposition', cd.disposition)
           ORDER BY io.ordinal, so.clause_ordinal) AS l
    FROM private.interpretation_observation io
    JOIN private.source_observation so ON so.id = io.observation_id
    LEFT JOIN private.clause_disposition_current cd ON cd.observation_id = so.id
   WHERE io.interpretation_id IN (SELECT id FROM v1)
   GROUP BY io.interpretation_id
), prop_rows AS (
  SELECT v1.interpretation_key::text AS k, to_jsonb(r)::text AS t
    FROM v1 LEFT JOIN links ON links.id = v1.id
    LEFT JOIN private.source_persona sp ON sp.id = v1.source_persona_id
   CROSS JOIN LATERAL (SELECT v1.interpretation_key AS key, v1.predicate, v1.interpretation_kind,
          private.interpretation_proposal_canonical_json_sha256(v1.value) AS value_sha256,
          v1.confidence, sp.persona_key, v1.schema_version, v1.method, v1.model_version,
          v1.prompt_version, v1.derivation_kind, coalesce(links.l, '[]'::jsonb) AS links) r
), cur AS (
  SELECT ic.* FROM private.interpretation_current ic WHERE ic.source_id = :src
), dec_rows AS (
  SELECT cur.interpretation_key::text AS k, to_jsonb(r)::text AS t
    FROM cur CROSS JOIN LATERAL (SELECT cur.interpretation_key AS key, cur.version, cur.status,
          CASE WHEN cur.decision_evidence IS NULL THEN NULL ELSE cur.decision_evidence - 'pack_sha256' END AS evidence,
          CASE WHEN cur.decided_by IS NULL THEN NULL
               ELSE encode(extensions.digest(convert_to(cur.decided_by::text,'UTF8'),'sha256'),'hex') END
            AS decided_by_sha256) r
   WHERE cur.version > 1 OR cur.status <> 'proposed'
), bind_rows AS (
  SELECT i.interpretation_key::text AS k, p.target_type, p.target_id::text AS tid,
         to_jsonb(r)::text AS t
    FROM private.interpretation_promotion p
    JOIN private.interpretation i ON i.id = p.interpretation_id
   CROSS JOIN LATERAL (SELECT i.interpretation_key AS key, p.target_type, p.target_id, p.rule_key, p.rule_version) r
   WHERE i.source_id = :src
), h AS (
  SELECT
    (SELECT count(*) FROM prop_rows) AS n_interpretations,
    encode(extensions.digest(convert_to(coalesce((SELECT string_agg(t, E'\n' ORDER BY k COLLATE "C") FROM prop_rows),''),'UTF8'),'sha256'),'hex') AS proposal_digest,
    (SELECT count(*) FROM cur WHERE version > 1 OR status <> 'proposed') AS n_decided,
    coalesce((SELECT jsonb_object_agg(ms, n) FROM (
       SELECT coalesce(decision_evidence->>'method','') || '|' || status AS ms, count(*) AS n
         FROM cur WHERE version > 1 OR status <> 'proposed' GROUP BY 1) x), '{}'::jsonb) AS decided_by_method_status,
    encode(extensions.digest(convert_to(coalesce((SELECT string_agg(t, E'\n' ORDER BY k COLLATE "C") FROM dec_rows),''),'UTF8'),'sha256'),'hex') AS decision_digest,
    (SELECT count(*) FROM bind_rows) AS n_bindings,
    encode(extensions.digest(convert_to(coalesce((SELECT string_agg(t, E'\n' ORDER BY k COLLATE "C", target_type COLLATE "C", tid COLLATE "C", t COLLATE "C") FROM bind_rows),''),'UTF8'),'sha256'),'hex') AS binding_digest
)
SELECT set_config('daa.transfer_digests', to_jsonb(h)::text, false) AS transfer_digests FROM h;
