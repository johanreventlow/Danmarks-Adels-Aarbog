-- Trin 6c-3 / 6d-3 (blok a6b-resten): rækkefil til forælderarket, kontrakt relation-parent-sheet-input-v2.
-- Læse-kun. Rækkerne bærer nu KONTEKST, så et kort kan bedømmes uden at slå op: postens gældende tekst
-- (helpost_text_current), den citerede klausul med side og offsets, postens nøgle, barnets (hovedpersonens) navn og
-- datoer samt for hver familie-kandidat familiens forældre (partnere) og børn med navne og datoer.
-- Funktionen private.relation_structural_candidates er REVOKE'd fra authenticated, så scriptet kører som den
-- forbindelsesrolle, der ejer læsningen (ikke SET ROLE). Kør:
--   PGCLIENTENCODING=UTF8 env -u PGOPTIONS psql -XAtq -v source=1 -f relation_parent_rows.sql > ~/.private/…/rows.json
-- Rækkefilen er præcis projektionens ::text + én LF.
-- PII: filen indeholder NAVNE og BOGENS TEKST (også om levende personer) → den SKAL ligge under ~/.private (0600),
-- aldrig i repoet og aldrig sendt til en model. Værktøjet (relation_parent_sheet.py) vælger ikke selv stedet; det
-- tjekker kun --private-root. Fladt datagrundlag: hver kandidat bærer partners/children i fast rækkefølge.
\set ON_ERROR_STOP on
BEGIN;
SET TRANSACTION READ ONLY;
SET LOCAL TimeZone='UTC';
SELECT jsonb_build_object(
  'contract', 'relation-parent-sheet-input-v2',
  'source_id', :source::bigint,
  'rows', coalesce(jsonb_agg(jsonb_build_object(
      'row_no', t.rn,
      'interpretation_key', t.interpretation_key,
      'interpretation_version', t.version,
      'principal_persona_id', t.principal_persona_id,
      'principal', t.principal,
      'record_key', t.record_key,
      'post_text', t.post_text,
      'clauses', t.clauses,
      'candidates', t.candidates) ORDER BY t.rn), '[]'::jsonb))::text
FROM (
  SELECT row_number() OVER (ORDER BY ic.interpretation_key) AS rn,
         ic.interpretation_key, ic.version, pc.source_persona_id AS principal_persona_id,
         (SELECT jsonb_build_object('person_id', pp.id, 'navn', coalesce(pp.visning_fuldt_navn, pp.visning_navn),
                                    'foedt', pp.visning_foedt, 'doed', pp.visning_doed, 'levende', pp.levende)
            FROM private.source_persona_identity pi
            JOIN public.person pp ON pp.id=pi.canonical_person_id
           WHERE pi.source_persona_id=pc.source_persona_id AND pi.decision_status='accepted') AS principal,
         cl.record_key, cl.post_text, coalesce(cl.clauses, '[]'::jsonb) AS clauses,
         coalesce((SELECT jsonb_agg(jsonb_build_object(
                         'family_id', c.family_id,
                         'counterpart_persona_id', c.counterpart_persona_id,
                         'counterpart_person_id', c.counterpart_person_id,
                         'partners', coalesce((SELECT jsonb_agg(jsonb_build_object('person_id', p.id,
                                    'navn', coalesce(p.visning_fuldt_navn, p.visning_navn),
                                    'foedt', p.visning_foedt, 'doed', p.visning_doed, 'levende', p.levende)
                                    ORDER BY fm.ordinal NULLS LAST, p.visning_foedt COLLATE "C" NULLS LAST, p.id)
                                 FROM public.family_member fm JOIN public.person p ON p.id=fm.person_id
                                WHERE fm.family_id=c.family_id AND fm.rolle='partner'), '[]'::jsonb),
                         'children', coalesce((SELECT jsonb_agg(jsonb_build_object('person_id', p.id,
                                    'navn', coalesce(p.visning_fuldt_navn, p.visning_navn),
                                    'foedt', p.visning_foedt, 'doed', p.visning_doed, 'levende', p.levende)
                                    ORDER BY fm.ordinal NULLS LAST, p.visning_foedt COLLATE "C" NULLS LAST, p.id)
                                 FROM public.family_member fm JOIN public.person p ON p.id=fm.person_id
                                WHERE fm.family_id=c.family_id AND fm.rolle='barn'), '[]'::jsonb))
                       ORDER BY c.family_id, c.counterpart_person_id)
                     FROM private.relation_structural_candidates(ic.interpretation_key) c), '[]'::jsonb) AS candidates
    FROM private.interpretation_current ic
    JOIN private.interpretation_party_current pc
      ON pc.interpretation_key=ic.interpretation_key AND pc.party_role='principal'
    LEFT JOIN LATERAL (
      SELECT (SELECT sr.record_key FROM private.source_record_anchor_current a
                JOIN private.source_record sr ON sr.id=a.source_record_id
               WHERE a.occurrence_id=min(co.occurrence_id::text)::uuid AND a.decision_status='accepted'
               ORDER BY sr.record_key LIMIT 1) AS record_key,
             (SELECT pt.verbatim_text FROM private.helpost_text_current(min(co.parent_observation_id::text)::uuid) pt) AS post_text,
             jsonb_agg(jsonb_build_object('text', co.verbatim_text, 'page_from', co.page_from, 'page_to', co.page_to,
                                          'post_char_from', co.post_char_from, 'post_char_to', co.post_char_to)
                       ORDER BY io.ordinal) AS clauses
        FROM private.interpretation_observation io
        JOIN private.source_observation co ON co.id=io.observation_id
       WHERE io.interpretation_id=ic.id AND io.evidence_role='supporting'
    ) cl ON true
   WHERE ic.predicate='relation.parent' AND ic.status='proposed' AND ic.source_id=:source::bigint
) t;
ROLLBACK;
