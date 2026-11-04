-- Trin 6c-2a (vej B): referencen for public_person_facts. Definitionen er kopieret ordret fra main (ded0404a,
-- schema.sql:20045-20115) og FROSSET: den er målestokken for, at det set-baserede bindingstjek giver præcis samme
-- rækker. Opdatér den aldrig sammen med public_person_facts. Kun navnet er ændret (pg_temp.public_person_facts_ref);
-- grants er udeladt, da referencen kun kaldes af testens ejer.
CREATE OR REPLACE FUNCTION pg_temp.public_person_facts_ref(p_person_ids bigint[])
RETURNS TABLE(person_id bigint, fact_id bigint, faktatype text, conclusion_status text, assertion_id bigint,
  chosen boolean, vaerdi_tekst text, date_raw text, date_min date, date_max date, date_qualifier text,
  date_certainty text, source_id bigint, source_label text, side text, record_ref uuid, record_label text,
  citation_label text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
#variable_conflict use_column
BEGIN
  IF public.narrative_record_contract_version()<2 OR p_person_ids IS NULL THEN RETURN; END IF;
  RETURN QUERY
  WITH f AS (
    SELECT fa.id,fa.subjekt_id,fa.faktatype,cn.status,cn.valgt_assertion_id
      FROM public.fact fa
      JOIN public.conclusion cn ON cn.target_type='fact' AND cn.target_id=fa.id
     WHERE fa.subjekt_type='person' AND fa.subjekt_id=ANY(p_person_ids)
       AND cn.status IN ('afklaret','omstridt')
       AND public.entitet_offentlig('person',fa.subjekt_id)
  ), b AS (
    -- Gældende bindinger pr. assertion med deres eneste record (betingelse 1, 2 og 4).
    SELECT p.target_id AS assertion_id,p.id AS promotion_id,cur.source_id,
           (SELECT array_agg(an.source_record_id)
              FROM private.interpretation_observation io
              JOIN private.source_observation o ON o.id=io.observation_id
              JOIN private.source_record_anchor_current an ON an.occurrence_id=o.occurrence_id AND an.decision_status='accepted'
             WHERE io.interpretation_id=p.interpretation_id AND io.evidence_role='supporting') AS recs,
           (SELECT count(*) FROM private.interpretation_observation io
             WHERE io.interpretation_id=p.interpretation_id AND io.evidence_role='supporting') AS n_support
      FROM private.interpretation_promotion p
      JOIN private.interpretation q ON q.id=p.interpretation_id
      JOIN private.interpretation_current cur ON cur.interpretation_key=q.interpretation_key AND cur.id=p.interpretation_id
     WHERE p.target_type='assertion'
       AND p.target_id IN (SELECT a.id FROM public.assertion a JOIN f ON a.target_type='fact' AND a.target_id=f.id)
       AND private.assertion_binding_current(p.id)
  ), bp AS (
    -- Betingelse 2 og 3: én record i fortolkningens kilde, én publiceret narrativ for den.
    SELECT b.assertion_id,sr.public_ref,nrp.id AS binding_id,nrp.narrative_id
      FROM b
      JOIN private.source_record sr ON sr.id=b.recs[1] AND sr.source_id=b.source_id
      JOIN private.narrative_record_publication nrp ON nrp.source_record_id=sr.id AND nrp.status='published'
     WHERE b.n_support=1 AND cardinality(b.recs)=1
       AND (SELECT count(*) FROM private.narrative_record_publication x
             WHERE x.source_record_id=sr.id AND x.status='published')=1
  ), bn AS (
    -- Entydighed: præcis én gældende binding pr. assertion, ellers ingen.
    SELECT a.id AS assertion_id,
           (SELECT count(*) FROM b WHERE b.assertion_id=a.id) AS n_bind
      FROM public.assertion a JOIN f ON a.target_type='fact' AND a.target_id=f.id
  )
  SELECT f.subjekt_id,f.id,f.faktatype,f.status,a.id,
         coalesce(a.id=f.valgt_assertion_id,false),
         a.vaerdi_tekst,a.date_raw,a.date_min,a.date_max,a.date_qualifier,a.date_certainty,
         s.id,coalesce(s.udgave,s.titel),c.side,
         lab.public_ref,lab.record_label,lab.citation_label
    FROM f
    JOIN public.assertion a ON a.target_type='fact' AND a.target_id=f.id
    JOIN bn ON bn.assertion_id=a.id
    LEFT JOIN public.citation c ON c.assertion_id=a.id
    LEFT JOIN public.source s ON s.id=c.source_id
    LEFT JOIN LATERAL (
      SELECT bp.public_ref,ev.after_state #>> '{labels,record_label}' AS record_label,
             ev.after_state #>> '{labels,citation_label}' AS citation_label
        FROM bp
        JOIN public.narrative n ON n.id=bp.narrative_id
        JOIN LATERAL (SELECT e.after_state FROM private.narrative_publication_event e
                       WHERE e.binding_id=bp.binding_id ORDER BY e.stream_version DESC,e.id DESC LIMIT 1) ev ON true
       WHERE bp.assertion_id=a.id AND bn.n_bind=1
         AND n.subjekt_type='person' AND n.subjekt_id=f.subjekt_id
         AND public.person_daa_narrative_publication_allowed(n.id)
    ) lab ON true
   ORDER BY f.subjekt_id,f.id,a.id,c.id NULLS LAST;
END $$;
