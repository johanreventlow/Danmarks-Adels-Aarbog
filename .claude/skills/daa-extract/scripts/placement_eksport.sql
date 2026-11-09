-- #150/6d-1: placeringsgrundlag for én kilde som JSON til build_header_manifest.py (--records-json).
-- Kun koder og tal (ingen navne eller tekst): kildens entry-koder i trykt orden, én række pr. source_record med
-- tidligste accepterede forekomst (validatorens orden: ORDER BY page_from, char_from, id LIMIT 1, jf. schema.sql
-- validate_source_record_placement), forælder-barn-par og modparter. parents/legacy/counterparts går via IDENTITET
-- (primary-persona -> accepteret canonical_person_id -> family_member / person_external_id / relation samme_som),
-- ikke via record_key.
-- Brug (læsetransaktion): psql -X -At -v ON_ERROR_STOP=1 -v src=N -f placement_eksport.sql > ~/.private/6d1/records.json
\set QUIET on
BEGIN READ ONLY;
WITH first_occ AS (
  SELECT r.id AS record_id, r.record_key, r.record_kind, o.page_from, o.char_from
    FROM private.source_record r
    JOIN LATERAL (
      SELECT occ.page_from, occ.char_from
        FROM private.source_record_anchor_current a
        JOIN private.source_record_occurrence occ ON occ.id = a.occurrence_id
       WHERE a.source_record_id = r.id AND a.decision_status = 'accepted'
       ORDER BY occ.page_from, occ.char_from, occ.id LIMIT 1
    ) o ON true
   WHERE r.source_id = :src
), rec_person AS (   -- recordens principal: primary-mention paa en rod-observation i en accepteret forekomst
  SELECT DISTINCT r.record_key, i.canonical_person_id AS person_id
    FROM private.source_record r
    JOIN private.source_record_anchor_current a ON a.source_record_id = r.id AND a.decision_status = 'accepted'
    JOIN private.source_observation ob ON ob.occurrence_id = a.occurrence_id AND ob.parent_observation_id IS NULL
    JOIN private.source_mention sm ON sm.observation_id = ob.id
    JOIN private.source_persona_mention spm ON spm.mention_id = sm.id AND spm.mention_role = 'primary'
    JOIN private.source_persona_identity i ON i.source_persona_id = spm.persona_id
     AND i.decision_status = 'accepted' AND i.canonical_person_id IS NOT NULL
   WHERE r.source_id = :src
)
SELECT jsonb_build_object(
  'entries', (SELECT coalesce(jsonb_agg(e.code ORDER BY e.sort_order), '[]'::jsonb)
                FROM public.lineage_scheme s JOIN public.lineage_scheme_entry e ON e.scheme_id = s.id
               WHERE s.source_id = :src AND s.kind = 'stamtavle'),
  'records', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                'record_key', f.record_key, 'record_kind', f.record_kind,
                'page_from', f.page_from, 'char_from', f.char_from,
                'persona', EXISTS (  -- primary-persona paa recordens helpost (rod-observation), uanset identitetsstatus
                  SELECT 1 FROM private.source_record_anchor_current a
                    JOIN private.source_observation ob ON ob.occurrence_id = a.occurrence_id
                     AND ob.parent_observation_id IS NULL
                    JOIN private.source_mention sm ON sm.observation_id = ob.id
                    JOIN private.source_persona_mention spm ON spm.mention_id = sm.id AND spm.mention_role = 'primary'
                   WHERE a.source_record_id = f.record_id AND a.decision_status = 'accepted'),
                'legacy', (SELECT jsonb_build_object('linje', pe.linje, 'nr', pe.nr)
                             FROM rec_person rp
                             JOIN public.person_external_id pe ON pe.person_id = rp.person_id AND pe.source_id = :src
                            WHERE rp.record_key = f.record_key
                            ORDER BY pe.linje, pe.nr LIMIT 1)
              ) ORDER BY f.record_key), '[]'::jsonb)
                FROM first_occ f),
  'parents', (SELECT coalesce(jsonb_agg(DISTINCT jsonb_build_object('child', c.record_key, 'parent', p.record_key)),
                              '[]'::jsonb)
                FROM public.family_member b
                JOIN public.family_member pa ON pa.family_id = b.family_id AND pa.rolle = 'partner'
                JOIN rec_person c ON c.person_id = b.person_id
                JOIN rec_person p ON p.person_id = pa.person_id
               WHERE b.rolle = 'barn'),
  'counterparts', (SELECT coalesce(jsonb_agg(DISTINCT jsonb_build_object(
                     'record_key', rp.record_key, 'lineage_kode', pe.linje, 'source_id', pe.source_id)),
                     '[]'::jsonb)
                     FROM rec_person rp
                     JOIN public.relation rel ON rel.rolle = 'samme_som'
                      AND rel.subjekt_type = 'person' AND rel.objekt_type = 'person'
                      AND rp.person_id IN (rel.subjekt_id, rel.objekt_id)
                     JOIN public.conclusion cn ON cn.target_type = 'relation' AND cn.target_id = rel.id
                      AND cn.status = 'afklaret'   -- kun afklarede samme_som
                     JOIN public.person_external_id pe
                       ON pe.person_id = CASE WHEN rel.subjekt_id = rp.person_id THEN rel.objekt_id ELSE rel.subjekt_id END
                      AND pe.source_id <> :src AND pe.linje IS NOT NULL)
)::text;
ROLLBACK;
