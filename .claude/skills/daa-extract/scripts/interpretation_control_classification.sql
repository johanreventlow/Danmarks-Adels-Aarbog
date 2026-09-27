-- Kontrolmodellens klassifikation (decisions 2026-09-27; plan 2026-09-27 Task 1).
-- Læse-kun. Klassificerer hvert `proposed` forslag med en aktiv promotionregel efter,
-- hvordan dets værdi forholder sig til databasens assertions på den identificerede person:
--   MATCH / MATCH_SINGLETON  præcis ét mål under RPC'ens normalisering (bulk / ikke-bulk)
--   AMBIGUOUS                flere mål matcher
--   SKRIVEMAADE              intet eksakt mål, men samme tegn uden tegnsætning, eller samme tal
--   NO_FACT                  personen har intet faktum af typen, eller kun uden værdi
--   REAL_DIFF                værdien er reelt en anden end databasens
--   NO_IDENTITY / NO_PLACEMENT / UNSUPPORTED_RULE  som i målfindingen
-- MATCH-udtrykket er BYTE-IDENTISK med interpretation_promotion_targets.sql og RPC'en:
-- lower(btrim(normalize(x,NFC))). SKRIVEMAADE er kun en klassifikation; den ændrer aldrig
-- en status. Regelflagene spejles fra målfindingen, så et MATCH her også er et MATCH dér,
-- når forslaget er accepteret (tests/sql/test-interpretation-control-classification.sql).
-- Resultatet printes og gemmes i `daa.control_result`.
WITH prop AS (
  SELECT ic.id AS interpretation_id, ic.version, ic.predicate, ic.value #>> '{}' AS v,
         spi.canonical_person_id AS pid, r.expected_fact_type, r.value_kind,
         r.requires_persona_identity, r.requires_principal_placement, r.bulk_eligible,
         EXISTS (SELECT 1 FROM private.source_persona_placement_current pl
                  WHERE pl.source_persona_id = ic.source_persona_id
                    AND pl.decision_status = 'accepted'
                    AND pl.placement_role IN ('principal_member','co_principal')) AS has_placement
    FROM private.interpretation_current ic
    JOIN private.interpretation_promotion_rule_current r
      ON r.predicate = ic.predicate AND r.interpretation_kind = ic.interpretation_kind
     AND r.target_type = 'assertion' AND r.status = 'active'
    LEFT JOIN private.source_persona_identity spi
      ON spi.source_persona_id = ic.source_persona_id AND spi.decision_status = 'accepted'
   WHERE ic.status = 'proposed'
), kanon AS (
  SELECT prop.interpretation_id, a.id AS assertion_id,
         CASE prop.value_kind WHEN 'text' THEN a.vaerdi_tekst
                              WHEN 'date_raw' THEN a.date_raw END AS k
    FROM prop
    JOIN public.fact f ON f.subjekt_type = 'person' AND f.subjekt_id = prop.pid
                      AND f.faktatype = prop.expected_fact_type
    JOIN public.assertion a ON a.target_type = 'fact' AND a.target_id = f.id
), sammenlignet AS (
  SELECT prop.interpretation_id,
         count(kanon.k) AS n_vaerdi,
         count(*) FILTER (WHERE lower(btrim(normalize(prop.v, NFC)))
                              = lower(btrim(normalize(kanon.k, NFC)))) AS n_eksakt,
         min(kanon.assertion_id) FILTER (WHERE lower(btrim(normalize(prop.v, NFC)))
                                             = lower(btrim(normalize(kanon.k, NFC)))) AS assertion_id,
         bool_or(regexp_replace(lower(normalize(kanon.k, NFC)), '[^[:alnum:]]+', '', 'g')
                   = regexp_replace(lower(normalize(prop.v, NFC)), '[^[:alnum:]]+', '', 'g')
                 OR (regexp_replace(kanon.k, '[^0-9]+', '', 'g') <> ''
                     AND regexp_replace(kanon.k, '[^0-9]+', '', 'g')
                       = regexp_replace(prop.v, '[^0-9]+', '', 'g'))) AS skrivemaade
    FROM prop LEFT JOIN kanon USING (interpretation_id)
   GROUP BY prop.interpretation_id
), klasse AS (
  SELECT p.interpretation_id, p.version, p.predicate,
         CASE WHEN NOT p.requires_persona_identity THEN 'UNSUPPORTED_RULE'
              WHEN p.pid IS NULL THEN 'NO_IDENTITY'
              WHEN p.requires_principal_placement AND NOT p.has_placement THEN 'NO_PLACEMENT'
              WHEN s.n_eksakt > 1 THEN 'AMBIGUOUS'
              WHEN s.n_eksakt = 1 AND NOT p.bulk_eligible THEN 'MATCH_SINGLETON'
              WHEN s.n_eksakt = 1 THEN 'MATCH'
              WHEN s.n_vaerdi = 0 THEN 'NO_FACT'
              WHEN s.skrivemaade THEN 'SKRIVEMAADE'
              ELSE 'REAL_DIFF' END AS class,
         s.assertion_id
    FROM prop p JOIN sammenlignet s USING (interpretation_id)
), classes(class) AS (
  VALUES ('MATCH'),('MATCH_SINGLETON'),('AMBIGUOUS'),('SKRIVEMAADE'),('NO_FACT'),('REAL_DIFF'),
         ('NO_IDENTITY'),('NO_PLACEMENT'),('UNSUPPORTED_RULE')
), grid AS (
  SELECT p.predicate, c.class,
         (SELECT count(*) FROM klasse k WHERE k.predicate = p.predicate AND k.class = c.class) AS n
    FROM (SELECT DISTINCT predicate FROM prop) p CROSS JOIN classes c
), result AS (
  SELECT jsonb_build_object(
    'items', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'interpretation_id', k.interpretation_id, 'version', k.version, 'predicate', k.predicate,
        'class', k.class,
        'assertion_id', CASE WHEN k.class IN ('MATCH','MATCH_SINGLETON') THEN k.assertion_id END)
        ORDER BY k.interpretation_id) FROM klasse k), '[]'::jsonb),
    'counts', coalesce((SELECT jsonb_object_agg(predicate, c) FROM (
        SELECT predicate, jsonb_object_agg(class, n) AS c FROM grid GROUP BY predicate) x),
      '{}'::jsonb)) AS j
)
SELECT set_config('daa.control_result', j::text, false) AS control FROM result;
