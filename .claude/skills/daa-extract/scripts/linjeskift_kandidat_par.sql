-- Fælles psql-snippet (\ir): linjeskift-v1-kandidaterne som par (spec 2026-11-02 §4.4 pkt. 4). Bruges af
-- linjeskift_kandidater.sql (GO-pakken) og af ceremoni 3's runner (i skrive-transaktionen kræves en identisk parliste),
-- så afgrænsningen kun står ét sted. Afgrænsningen K1-K6 er beskrevet i linjeskift_kandidater.sql's header.
-- Kræver 6c-2a og 6c-2b (binding_value_matches, saml_blanktegn_v1, paastand_korrektion).
-- Ind:  GUC daa.linjeskift_kilde = kildens id (fra kalderens -v source_id; aldrig fast i koden).
-- Ud (transaktionslokal GUC; intet skrives ud):
--   daa.linjeskift_kandidat_par  '<assertion_id>:<interpretation_id>' kommasepareret, stigende på assertion_id som
--                                bigint; tom streng uden kandidater. interpretation_id er forslagets aktuelle version.
WITH regel AS (
  SELECT DISTINCT pp.predicate, pp.interpretation_kind, pp.expected_fact_type
    FROM private.interpretation_predicate_promotable pp
   WHERE pp.value_kind='date_raw'
), fortolk AS (
  -- alle kilders aktuelle datofortolkninger (proposed/accepted) med accepteret identitet
  SELECT ic.id, ic.interpretation_key, ic.source_id, ic.value, i.canonical_person_id AS pid, r.expected_fact_type
    FROM private.interpretation_current ic
    JOIN regel r ON r.predicate=ic.predicate AND r.interpretation_kind=ic.interpretation_kind
    JOIN private.source_persona_identity i
      ON i.source_persona_id=ic.source_persona_id AND i.decision_status='accepted' AND i.canonical_person_id IS NOT NULL
   WHERE ic.status IN ('proposed','accepted') AND jsonb_typeof(ic.value)='string'
), maal AS (
  SELECT fo.id, fo.interpretation_key, fo.source_id, a.id AS assertion_id,
         private.binding_value_matches('date_raw',fo.value,NULL,private.saml_blanktegn_v1(a.date_raw)) AS samlet_lig
    FROM fortolk fo
    JOIN public.fact f ON f.subjekt_type='person' AND f.subjekt_id=fo.pid AND f.faktatype=fo.expected_fact_type
    JOIN public.assertion a ON a.target_type='fact' AND a.target_id=f.id
   WHERE private.binding_value_matches('date_raw',fo.value,NULL,a.date_raw)
      OR private.binding_value_matches('date_raw',fo.value,NULL,private.saml_blanktegn_v1(a.date_raw))
), eneste AS (
  -- K1+K2: kildens forslag med præcis ét mål
  SELECT m.id, (array_agg(m.interpretation_key))[1] AS interpretation_key, min(m.source_id) AS source_id,
         min(m.assertion_id) AS assertion_id, bool_and(m.samlet_lig) AS samlet_lig
    FROM maal m
   WHERE m.source_id=current_setting('daa.linjeskift_kilde')::bigint
   GROUP BY m.id HAVING count(*)=1
), kandidat AS (
  SELECT e.assertion_id, e.id AS interpretation_id
    FROM eneste e
    JOIN public.assertion a ON a.id=e.assertion_id
   WHERE e.samlet_lig                                                           -- K3
     AND a.date_raw IS DISTINCT FROM private.saml_blanktegn_v1(a.date_raw)      -- K4
     AND ARRAY(SELECT DISTINCT c.source_id FROM public.citation c WHERE c.assertion_id=a.id ORDER BY 1)
         = ARRAY[e.source_id]                                                   -- K5
     AND NOT EXISTS (                                                           -- K2: ingen anden nøgle efter rettelsen
       SELECT 1 FROM maal o WHERE o.assertion_id=a.id AND o.samlet_lig AND o.interpretation_key<>e.interpretation_key)
     AND NOT EXISTS (                                                           -- K2: ét forslag retter én påstand
       SELECT 1 FROM public.paastand_korrektion k JOIN private.interpretation q ON q.id=k.interpretation_id
        WHERE q.interpretation_key=e.interpretation_key AND k.assertion_id<>a.id
          AND NOT EXISTS (SELECT 1 FROM public.change_set rv WHERE rv.reverterer_id=k.change_set_id))
     AND NOT EXISTS (
       SELECT 1 FROM private.interpretation_promotion p JOIN private.interpretation q ON q.id=p.interpretation_id
        WHERE q.interpretation_key=e.interpretation_key AND p.target_type='assertion' AND p.target_id<>a.id
          AND private.assertion_binding_current(p.id))
     AND NOT EXISTS (                                                           -- K6
       SELECT 1
         FROM private.interpretation_promotion p
         JOIN private.interpretation q ON q.id=p.interpretation_id
         JOIN private.interpretation_current cur
           ON cur.interpretation_key=q.interpretation_key AND cur.id=p.interpretation_id
         JOIN private.interpretation_promotion_rule r ON r.rule_key=p.rule_key AND r.rule_version=p.rule_version
        WHERE p.target_type='assertion' AND p.target_id=a.id
          AND private.assertion_binding_current(p.id)
          AND NOT private.binding_value_matches(r.value_kind,cur.value,a.vaerdi_tekst,
                                                private.saml_blanktegn_v1(a.date_raw)))
)
SELECT set_config('daa.linjeskift_kandidat_par',
         coalesce(string_agg(k.assertion_id::text||':'||k.interpretation_id::text,',' ORDER BY k.assertion_id),''),true)
  FROM kandidat k \g /dev/null
