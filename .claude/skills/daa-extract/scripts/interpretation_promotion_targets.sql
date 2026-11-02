-- Bindingsmål for accepterede, promoverbare fortolkninger (spec §8.3).
-- Spejler private.validate_interpretation_promotion_items: samme regelvalg,
-- regelflag (identitet, principal-placering, bulk), eksisterende promotions og
-- normalisering. Et entydigt mål under en bulk-regel er MATCH og går i `items`
-- (ét batch-kald); under en ikke-bulk-regel er det MATCH_SINGLETON og går i
-- `singleton_items` (RPC'en godkender det kun i et kald med netop ét item).
-- En eksisterende promotion tæller kun, hvis den har PRÆCIS samme mål — som i RPC'en
-- (4.5-kodereview, fund 4). Bevidst strengere end RPC'en: flere mulige mål er
-- AMBIGUOUS og bindes ikke, og en regel uden identitetskrav er UNSUPPORTED_RULE.
-- Alle udfald tælles med 0-fyld.
-- Trin 6c-2:
--   ALREADY_BOUND_OTHER  (efter ALREADY_PROMOTED, som i RPC'en) en anden fortolkning (anden interpretation_key, fra
--                        enhver kilde) har en gældende binding på målet (private.assertion_binding_current); leveres
--                        aldrig, med eller uden kildescope
--   TARGET_SHARED        KUN når daa.control_src er sat (v2-vejen): to eller flere forskellige fortolkninger ville være
--                        MATCH/MATCH_SINGLETON på samme påstand, uanset persona og kilde; ingen af dem leveres
-- Uden kildescope (v1-vejen: control_model.py, overførslens scopede målfinding) beregnes TARGET_SHARED IKKE, og to
-- nøgler mod samme påstand leveres begge som MATCH. Værnet er da RPC'ens ALREADY_BOUND_OTHER: to nøgler mod samme
-- påstand i ét batch afvises atomisk, og intet skrives (private.validate_interpretation_promotion_items). Overførslens
-- wrapper udvælger pakkens nøgler efter denne fil, så en anden kildes accepterede, ubundne forslag må ikke spærre her
-- (tests/sql/transfer-decide-bind.sh; controller-afgørelse 2026-11-02, trin 6c-2 Task 6, valg A).
-- De to nye udfald 0-fyldes kun, når de forekommer i resultatet (så outputtet er byte-ens med før, når de ikke gør).
-- Kildescope (valgfrit): er GUC'en `daa.control_src` sat (ikke tom), medtages kun fortolkninger med
-- ic.source_id = current_setting('daa.control_src')::bigint i items og counts; udfaldene beregnes over alle kilder.
WITH acc AS (
  SELECT ic.id AS interpretation_id, ic.interpretation_key, ic.predicate, ic.value #>> '{}' AS v,
         spi.canonical_person_id AS pid, r.expected_fact_type, r.value_kind,
         r.requires_persona_identity, r.requires_principal_placement, r.bulk_eligible,
         EXISTS (SELECT 1 FROM private.source_persona_placement_current pl
                  WHERE pl.source_persona_id = ic.source_persona_id
                    AND pl.decision_status = 'accepted'
                    AND pl.placement_role IN ('principal_member','co_principal')) AS has_placement,
         CASE WHEN nullif(current_setting('daa.control_src', true), '') IS NULL THEN true
              ELSE ic.source_id = current_setting('daa.control_src')::bigint END AS in_scope
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
), matched AS (
  SELECT acc.*, count(cand.assertion_id) AS n_cand, min(cand.assertion_id) AS assertion_id
    FROM acc LEFT JOIN cand USING (interpretation_id)
   GROUP BY acc.interpretation_id, acc.interpretation_key, acc.predicate, acc.v, acc.pid, acc.expected_fact_type,
            acc.value_kind, acc.requires_persona_identity, acc.requires_principal_placement,
            acc.bulk_eligible, acc.has_placement, acc.in_scope
), targets0 AS (
  SELECT m.interpretation_id, m.interpretation_key, m.predicate, m.assertion_id, m.in_scope,
         CASE WHEN NOT m.requires_persona_identity THEN 'UNSUPPORTED_RULE'
              WHEN m.pid IS NULL THEN 'NO_IDENTITY'
              WHEN m.requires_principal_placement AND NOT m.has_placement THEN 'NO_PLACEMENT'
              WHEN m.n_cand = 0 THEN 'NO_MATCH'
              WHEN m.n_cand > 1 THEN 'AMBIGUOUS'
              WHEN EXISTS (SELECT 1 FROM private.interpretation_promotion pr
                            WHERE pr.interpretation_id = m.interpretation_id
                              AND pr.target_type = 'assertion'
                              AND pr.target_id = m.assertion_id) THEN 'ALREADY_PROMOTED'
              WHEN EXISTS (SELECT 1 FROM private.interpretation_promotion op
                             JOIN private.interpretation oi ON oi.id = op.interpretation_id
                            WHERE op.target_type = 'assertion' AND op.target_id = m.assertion_id
                              AND oi.interpretation_key <> m.interpretation_key
                              AND private.assertion_binding_current(op.id)) THEN 'ALREADY_BOUND_OTHER'
              WHEN NOT m.bulk_eligible THEN 'MATCH_SINGLETON'
              ELSE 'MATCH' END AS outcome
    FROM matched m
), delt AS (
  -- Påstande, som to eller flere forskellige fortolkninger (alle kilder) ville binde.
  SELECT assertion_id FROM targets0 WHERE outcome IN ('MATCH','MATCH_SINGLETON')
   GROUP BY assertion_id HAVING count(DISTINCT interpretation_key) > 1
), targets AS (
  SELECT t.interpretation_id, t.predicate, t.assertion_id,
         CASE WHEN nullif(current_setting('daa.control_src', true), '') IS NOT NULL
                   AND t.outcome IN ('MATCH','MATCH_SINGLETON') AND t.assertion_id IN (SELECT assertion_id FROM delt)
              THEN 'TARGET_SHARED' ELSE t.outcome END AS outcome
    FROM targets0 t WHERE t.in_scope
), outcomes(outcome) AS (
  VALUES ('MATCH'),('MATCH_SINGLETON'),('NO_MATCH'),('AMBIGUOUS'),('NO_IDENTITY'),
         ('NO_PLACEMENT'),('ALREADY_PROMOTED'),('UNSUPPORTED_RULE')
  UNION ALL
  SELECT o FROM (VALUES ('ALREADY_BOUND_OTHER'),('TARGET_SHARED')) n(o)
   WHERE EXISTS (SELECT 1 FROM targets t WHERE t.outcome = n.o)
), grid AS (
  SELECT p.predicate, o.outcome,
         (SELECT count(*) FROM targets t WHERE t.predicate = p.predicate AND t.outcome = o.outcome) AS n
    FROM (SELECT DISTINCT predicate FROM acc WHERE in_scope) p CROSS JOIN outcomes o
), result AS (
  SELECT jsonb_build_object(
    'items', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'interpretation_id', t.interpretation_id, 'target_type', 'assertion',
        'target_id', t.assertion_id) ORDER BY t.interpretation_id)
      FROM targets t WHERE t.outcome = 'MATCH'), '[]'::jsonb),
    'singleton_items', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'interpretation_id', t.interpretation_id, 'target_type', 'assertion',
        'target_id', t.assertion_id) ORDER BY t.interpretation_id)
      FROM targets t WHERE t.outcome = 'MATCH_SINGLETON'), '[]'::jsonb),
    'counts', coalesce((SELECT jsonb_object_agg(predicate, c) FROM (
        SELECT predicate, jsonb_object_agg(outcome, n) AS c FROM grid GROUP BY predicate) x),
      '{}'::jsonb)) AS j
)
SELECT set_config('daa.targets_result', j::text, false) AS targets FROM result;
