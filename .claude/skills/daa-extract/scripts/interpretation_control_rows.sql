-- Rækkefilen til afgørelsesarket: hvert `proposed` forslag med postens nøgle, værdi og de
-- citerede klausuler (plan 4.5 Task 5 Step 5, ordret; plan 2026-09-27 Task 2). Læse-kun.
-- Output indeholder klausultekst: skriv det til en 0600-fil, og læs det aldrig — kun tæl.
-- `value_text`: strengen selv, eller `raw` for objekter (4.3b-arkets regel).
-- Kildescope (trin 6c-2, valgfrit): er GUC'en `daa.control_src` sat (ikke tom), medtages kun forslag med
-- ic.source_id = current_setting('daa.control_src')::bigint, og hver række får fem felter mere:
--   persona_id        forslagets persona (NULL uden persona)
--   identity_outcome  personaidentitetens evidence->>'outcome' (generatorens udfald; NULL uden)
--   identity_version  personaidentitetens aktuelle version (uanset status; NULL uden identitet)
--   navn_forkortes    kun person.name: sand, hvis forslaget ville forkorte et af den identificerede persons navne
--                     (private.navn_forkortes, samme regel som PAASTAND_NAVN_FORKORTES i red_ret_paastand);
--                     NULL uden identitet eller navnepåstand; false for andre prædikater.
--   rettelse_maal     målet for »bogen har ret« (red_ret_paastand, trin 6c-2 Task 7): den identificerede persons påstand
--                     af regelens faktatype, som er citeret af præcis én kilde, og det er forslagets egen kilde
--                     (RPC'ens PAASTAND_KILDE_DELT-regel). Præcis én sådan påstand → {"assertion_id", "forventet",
--                     "graenser"}, hvor forventet er p_forventet, som kortet viser målet ({fact_id, faktatype,
--                     vaerdi_tekst, date_raw, valgt_assertion_id, citation_sources}), og graenser er påstandens
--                     {date_min, date_max, date_qualifier} (kontrolværktøjet tæller rettelser, der ændrer dem);
--                     ingen eller flere → NULL (B tilbydes ikke).
--                     Indeholder påstandens værdi: rækkefilen er 0600 og læses aldrig, kun tælles.
-- Uden GUC er outputtet byte-ens med før (de fem felter fjernes, og navn_forkortes/rettelse_maal beregnes ikke).
WITH ctl AS (SELECT nullif(current_setting('daa.control_src', true), '') AS src),
rows AS (
  SELECT ic.id AS interpretation_id, ic.version, sr.record_key, ic.predicate,
         CASE jsonb_typeof(ic.value) WHEN 'string' THEN ic.value #>> '{}' ELSE ic.value->>'raw' END AS value_text,
         ic.confidence, CASE WHEN ic.source_persona_id IS NULL THEN 'other' ELSE 'principal' END AS persona_role,
         jsonb_agg(jsonb_build_object('ordinal', so.clause_ordinal, 'text', so.verbatim_text,
                   'flags', coalesce(so.clause_flags, '[]'::jsonb)) ORDER BY so.clause_ordinal) AS cited,
         ic.source_persona_id AS persona_id, spi.evidence->>'outcome' AS identity_outcome,
         spi.version AS identity_version
    FROM private.interpretation_current ic
    JOIN private.interpretation_observation io ON io.interpretation_id = ic.id
    JOIN private.source_observation so ON so.id = io.observation_id
    JOIN private.source_record_anchor_current ac ON ac.occurrence_id = so.occurrence_id
                                               AND ac.decision_status = 'accepted'
    JOIN private.source_record sr ON sr.id = ac.source_record_id
    LEFT JOIN private.source_persona_identity spi ON spi.source_persona_id = ic.source_persona_id
   WHERE ic.status = 'proposed'
     AND CASE WHEN (SELECT src FROM ctl) IS NULL THEN true
              ELSE ic.source_id = current_setting('daa.control_src')::bigint END
   GROUP BY ic.id, ic.version, sr.record_key, ic.predicate, ic.value, ic.confidence, ic.source_persona_id,
            spi.evidence->>'outcome', spi.version),
navn AS (
  -- Kun med kildescope: navnereglen mod den identificerede persons påstande af regelens faktatype.
  SELECT r.interpretation_id,
         bool_or(private.navn_forkortes(a.vaerdi_tekst, r.value_text)) AS navn_forkortes
    FROM rows r
    JOIN private.interpretation_current ic ON ic.id = r.interpretation_id
    JOIN private.interpretation_promotion_rule_current pr
      ON pr.predicate = ic.predicate AND pr.interpretation_kind = ic.interpretation_kind
     AND pr.target_type = 'assertion' AND pr.status = 'active' AND pr.value_kind = 'text'
    JOIN private.source_persona_identity i
      ON i.source_persona_id = ic.source_persona_id AND i.decision_status = 'accepted'
    JOIN public.fact f ON f.subjekt_type = 'person' AND f.subjekt_id = i.canonical_person_id
                      AND f.faktatype = pr.expected_fact_type
    JOIN public.assertion a ON a.target_type = 'fact' AND a.target_id = f.id
   WHERE (SELECT src FROM ctl) IS NOT NULL AND ic.predicate = 'person.name'
   GROUP BY r.interpretation_id),
maal0 AS (
  -- Kun med kildescope: kandidaterne til rettelsesmålet (samme regel- og identitetsjoin som navn).
  SELECT r.interpretation_id, a.id AS assertion_id,
         jsonb_build_object('fact_id', f.id, 'faktatype', f.faktatype, 'vaerdi_tekst', a.vaerdi_tekst,
                            'date_raw', a.date_raw, 'valgt_assertion_id', co.valgt_assertion_id,
                            'citation_sources', to_jsonb(cs.src)) AS forventet,
         jsonb_build_object('date_min', a.date_min, 'date_max', a.date_max,
                            'date_qualifier', a.date_qualifier) AS graenser
    FROM rows r
    JOIN private.interpretation_current ic ON ic.id = r.interpretation_id
    JOIN private.interpretation_promotion_rule_current pr
      ON pr.predicate = ic.predicate AND pr.interpretation_kind = ic.interpretation_kind
     AND pr.target_type = 'assertion' AND pr.status = 'active'
    JOIN private.source_persona_identity i
      ON i.source_persona_id = ic.source_persona_id AND i.decision_status = 'accepted'
    JOIN public.fact f ON f.subjekt_type = 'person' AND f.subjekt_id = i.canonical_person_id
                      AND f.faktatype = pr.expected_fact_type
    JOIN public.assertion a ON a.target_type = 'fact' AND a.target_id = f.id
    CROSS JOIN LATERAL (SELECT ARRAY(SELECT DISTINCT c.source_id FROM public.citation c
                                      WHERE c.assertion_id = a.id ORDER BY 1) AS src) cs
    LEFT JOIN public.conclusion co ON co.target_type = 'fact' AND co.target_id = f.id
   WHERE (SELECT src FROM ctl) IS NOT NULL AND cs.src = ARRAY[ic.source_id]),
maal AS (
  SELECT interpretation_id,
         CASE WHEN count(*) = 1
              THEN jsonb_build_object('assertion_id', min(assertion_id), 'forventet', (array_agg(forventet))[1],
                                      'graenser', (array_agg(graenser))[1]) END
           AS rettelse_maal
    FROM maal0 GROUP BY interpretation_id),
rows2 AS (
  SELECT r.*, CASE WHEN r.predicate = 'person.name' THEN n.navn_forkortes ELSE false END AS navn_forkortes,
         m.rettelse_maal
    FROM rows r LEFT JOIN navn n USING (interpretation_id) LEFT JOIN maal m USING (interpretation_id))
SELECT coalesce(jsonb_agg(CASE WHEN (SELECT src FROM ctl) IS NULL
                               THEN to_jsonb(rows2) - ARRAY['persona_id','identity_outcome','identity_version','navn_forkortes',
                                                       'rettelse_maal']
                               ELSE to_jsonb(rows2) END
                          ORDER BY record_key, predicate, interpretation_id), '[]') FROM rows2;
