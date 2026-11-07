-- Læse-kun mål til faktaforslag_rettelse.py klassificer (trin 6m del 2, Task 2): for hvert interpretation-id i GUC'en
-- `daa.faktaforslag_ids` (JSON-array af uuid'er) forslagets og målpåstandens aktuelle tilstand. Variabel: :src (kilde-id).
-- Kørsel: psql -qAtX -v ON_ERROR_STOP=1 -v src=3 -c "SET daa.faktaforslag_ids = '[...]'" -f <denne> > maal.json
-- Ét JSON-dokument ud. Rummer påstandsværdier: skriv kun til en 0600-fil; læs aldrig, tæl.
-- rettelse_maal beregnes som interpretation_control_rows.sql's (den identificerede persons påstand af regelens faktatype,
-- citeret af præcis én kilde = forslagets egen; præcis ét kandidat-mål, ellers NULL), men uanset forslagets status.
--   value_kind              regelens value_kind (private.interpretation_predicate_promotable), som binding_value_matches bruger
--   maal_bundet_af_anden    målet har en gyldig assertion-binding fra en interpretation med en ANDEN nøgle
--   egen_binding            en assertion-promotion af netop dette interpretation-id (gyldig = assertion_binding_current;
--                           en gyldig foretrækkes) med dens target_id; klassificer spærrer, hvis en gyldig binding
--                           ligger på en anden påstand end rettelse_maal (6c-2 valgte målet efter værdi)
--   gaeldende_id/_version   nøglens gældende række (interpretation_current)
--   tidligere               rækkens egen status, grund (decision_evidence 'grund' eller 'basis') og decided_at
BEGIN;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;
WITH ids AS (
  SELECT DISTINCT x::uuid AS id
    FROM jsonb_array_elements_text(current_setting('daa.faktaforslag_ids')::jsonb) AS t(x)),
f AS (
  SELECT i.id AS interpretation_id, i.interpretation_key, i.version, i.status, i.interpretation_kind, i.predicate,
         i.value, i.source_id, i.source_persona_id, i.decision_evidence, i.decided_at,
         spi.canonical_person_id AS person_id
    FROM ids JOIN private.interpretation i ON i.id = ids.id
    LEFT JOIN private.source_persona_identity spi
      ON spi.source_persona_id = i.source_persona_id AND spi.decision_status = 'accepted'),
maal0 AS (
  SELECT f.interpretation_id, a.id AS assertion_id, pp.value_kind,
         jsonb_build_object('fact_id', ft.id, 'faktatype', ft.faktatype, 'vaerdi_tekst', a.vaerdi_tekst,
                            'date_raw', a.date_raw, 'valgt_assertion_id', co.valgt_assertion_id,
                            'citation_sources', to_jsonb(cs.src)) AS forventet,
         jsonb_build_object('date_min', a.date_min, 'date_max', a.date_max,
                            'date_qualifier', a.date_qualifier) AS graenser
    FROM f
    JOIN private.interpretation_promotion_rule_current pr
      ON pr.predicate = f.predicate AND pr.interpretation_kind = f.interpretation_kind
     AND pr.target_type = 'assertion' AND pr.status = 'active'
    LEFT JOIN private.interpretation_predicate_promotable pp
      ON pp.predicate = f.predicate AND pp.interpretation_kind = f.interpretation_kind
    JOIN public.fact ft ON ft.subjekt_type = 'person' AND ft.subjekt_id = f.person_id
                       AND ft.faktatype = pr.expected_fact_type
    JOIN public.assertion a ON a.target_type = 'fact' AND a.target_id = ft.id
    CROSS JOIN LATERAL (SELECT ARRAY(SELECT DISTINCT c.source_id FROM public.citation c
                                      WHERE c.assertion_id = a.id ORDER BY 1) AS src) cs
    LEFT JOIN public.conclusion co ON co.target_type = 'fact' AND co.target_id = ft.id
   WHERE cs.src = ARRAY[f.source_id]),
maal AS MATERIALIZED (
  SELECT interpretation_id, min(assertion_id) AS assertion_id, (array_agg(value_kind))[1] AS value_kind,
         (array_agg(forventet))[1] AS forventet, (array_agg(graenser))[1] AS graenser
    FROM maal0 GROUP BY interpretation_id HAVING count(*) = 1),
rows AS (
  SELECT f.*, cur.id AS gaeldende_id, cur.version AS gaeldende_version, m.assertion_id,
         CASE WHEN m.interpretation_id IS NULL THEN NULL
              ELSE jsonb_build_object('assertion_id', m.assertion_id, 'forventet', m.forventet,
                                      'graenser', m.graenser, 'value_kind', m.value_kind) END AS rettelse_maal,
         (SELECT jsonb_build_object('promotion_id', p.id, 'gyldig', private.assertion_binding_current(p.id),
                                    'target_id', p.target_id)
            FROM private.interpretation_promotion p
           WHERE p.interpretation_id = f.interpretation_id AND p.target_type = 'assertion'
           ORDER BY private.assertion_binding_current(p.id) DESC, p.promoted_at DESC, p.id DESC LIMIT 1) AS egen_binding,
         (m.interpretation_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM private.interpretation_promotion p
              JOIN private.interpretation q ON q.id = p.interpretation_id
             WHERE p.target_type = 'assertion' AND p.target_id = m.assertion_id
               AND q.interpretation_key <> f.interpretation_key
               AND private.assertion_binding_current(p.id))) AS maal_bundet_af_anden
    FROM f
    LEFT JOIN private.interpretation_current cur ON cur.interpretation_key = f.interpretation_key
    LEFT JOIN maal m ON m.interpretation_id = f.interpretation_id)
SELECT jsonb_build_object('source_id', :src::bigint, 'forslag', coalesce(jsonb_agg(jsonb_build_object(
  'interpretation_id', interpretation_id, 'interpretation_key', interpretation_key, 'version', version,
  'status', status, 'gaeldende_id', gaeldende_id, 'gaeldende_version', gaeldende_version,
  'kind', interpretation_kind, 'predicate', predicate,
  'value_text', CASE jsonb_typeof(value) WHEN 'string' THEN value #>> '{}' ELSE value->>'raw' END,
  'value_type', jsonb_typeof(value), 'source_id', source_id, 'person_id', person_id,
  'tidligere', jsonb_build_object('status', status,
                                  'grund', coalesce(decision_evidence->>'grund', decision_evidence->>'basis'),
                                  'decided_at', decided_at),
  'egen_binding', egen_binding, 'rettelse_maal', rettelse_maal,
  'maal_bundet_af_anden', maal_bundet_af_anden) ORDER BY interpretation_id), '[]'::jsonb))
  FROM rows;
ROLLBACK;
