-- Bindingsmål for accepterede, promoverbare fortolkninger (spec §8.3).
-- Spejler private.validate_interpretation_promotion_items: samme regelvalg,
-- regelflag (identitet, principal-placering, bulk), eksisterende promotions og
-- normalisering. Kun MATCH bliver til items; alle andre udfald tælles med 0-fyld.
WITH acc AS (
  SELECT ic.id AS interpretation_id, ic.predicate, ic.value #>> '{}' AS v,
         spi.canonical_person_id AS pid, r.expected_fact_type, r.value_kind,
         r.requires_persona_identity, r.requires_principal_placement, r.bulk_eligible,
         EXISTS (SELECT 1 FROM private.source_persona_placement_current pl
                  WHERE pl.source_persona_id = ic.source_persona_id
                    AND pl.decision_status = 'accepted'
                    AND pl.placement_role IN ('principal_member','co_principal')) AS has_placement,
         EXISTS (SELECT 1 FROM private.interpretation_promotion pr
                  WHERE pr.interpretation_id = ic.id) AS already_promoted
    FROM private.interpretation_current ic
    JOIN private.interpretation_promotion_rule_current r
      ON r.predicate = ic.predicate AND r.interpretation_kind = ic.interpretation_kind
     AND r.target_type = 'assertion' AND r.status = 'active'
    LEFT JOIN private.source_persona_identity spi
      ON spi.source_persona_id = ic.source_persona_id AND spi.decision_status = 'accepted'
   WHERE ic.status = 'accepted'
), cand AS (
  SELECT acc.interpretation_id, a.id AS assertion_id
    FROM acc
    JOIN public.fact f ON f.subjekt_type = 'person' AND f.subjekt_id = acc.pid
                      AND f.faktatype = acc.expected_fact_type
    JOIN public.assertion a ON a.target_type = 'fact' AND a.target_id = f.id
   WHERE lower(btrim(normalize(acc.v, NFC))) = lower(btrim(normalize(
           CASE acc.value_kind WHEN 'text' THEN a.vaerdi_tekst
                               WHEN 'date_raw' THEN a.date_raw END, NFC)))
), targets AS (
  SELECT acc.interpretation_id, acc.predicate,
         CASE WHEN NOT acc.requires_persona_identity THEN 'UNSUPPORTED_RULE'
              WHEN acc.pid IS NULL THEN 'NO_IDENTITY'
              WHEN acc.requires_principal_placement AND NOT acc.has_placement THEN 'NO_PLACEMENT'
              WHEN NOT acc.bulk_eligible THEN 'NOT_BULK'
              WHEN acc.already_promoted THEN 'ALREADY_PROMOTED'
              WHEN count(cand.assertion_id) = 0 THEN 'NO_MATCH'
              WHEN count(cand.assertion_id) = 1 THEN 'MATCH'
              ELSE 'AMBIGUOUS' END AS outcome,
         min(cand.assertion_id) AS assertion_id
    FROM acc LEFT JOIN cand USING (interpretation_id)
   GROUP BY acc.interpretation_id, acc.predicate, acc.pid, acc.requires_persona_identity,
            acc.requires_principal_placement, acc.has_placement, acc.bulk_eligible,
            acc.already_promoted
), outcomes(outcome) AS (
  VALUES ('MATCH'),('NO_MATCH'),('AMBIGUOUS'),('NO_IDENTITY'),('NO_PLACEMENT'),
         ('NOT_BULK'),('ALREADY_PROMOTED'),('UNSUPPORTED_RULE')
), grid AS (
  SELECT p.predicate, o.outcome,
         (SELECT count(*) FROM targets t WHERE t.predicate = p.predicate AND t.outcome = o.outcome) AS n
    FROM (SELECT DISTINCT predicate FROM acc) p CROSS JOIN outcomes o
), result AS (
  SELECT jsonb_build_object(
    'items', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'interpretation_id', t.interpretation_id, 'target_type', 'assertion',
        'target_id', t.assertion_id) ORDER BY t.interpretation_id)
      FROM targets t WHERE t.outcome = 'MATCH'), '[]'::jsonb),
    'counts', coalesce((SELECT jsonb_object_agg(predicate, c) FROM (
        SELECT predicate, jsonb_object_agg(outcome, n) AS c FROM grid GROUP BY predicate) x),
      '{}'::jsonb)) AS j
)
SELECT set_config('daa.targets_result', j::text, false) AS targets FROM result;
