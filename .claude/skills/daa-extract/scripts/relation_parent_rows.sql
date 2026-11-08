-- Trin 6c-3 (blok a6b-resten): rækkefil til forælderarket. Læse-kun; ingen navne — kun nøgle, version,
-- principal-persona og familie-kandidater fra private.relation_structural_candidates.
-- Funktionen er REVOKE'd fra authenticated, så scriptet kører som den forbindelsesrolle, der ejer læsningen
-- (ikke SET ROLE). Kør:  PGCLIENTENCODING=UTF8 psql -XAtq -v source=1 -f relation_parent_rows.sql > rows.json
-- Rækkefilen er præcis projektionens ::text + én LF. Filen er ikke PII, men lægges under ~/.private som arket.
\set ON_ERROR_STOP on
BEGIN;
SET TRANSACTION READ ONLY;
SET LOCAL TimeZone='UTC';
SELECT jsonb_build_object(
  'contract', 'relation-parent-sheet-input-v1',
  'source_id', :source::bigint,
  'rows', coalesce(jsonb_agg(jsonb_build_object(
      'row_no', t.rn,
      'interpretation_key', t.interpretation_key,
      'interpretation_version', t.version,
      'principal_persona_id', t.principal_persona_id,
      'candidates', t.candidates) ORDER BY t.rn), '[]'::jsonb))::text
FROM (
  SELECT row_number() OVER (ORDER BY ic.interpretation_key) AS rn,
         ic.interpretation_key, ic.version, pc.source_persona_id AS principal_persona_id,
         coalesce((SELECT jsonb_agg(jsonb_build_object('family_id', c.family_id,
                                                       'counterpart_persona_id', c.counterpart_persona_id,
                                                       'counterpart_person_id', c.counterpart_person_id)
                                    ORDER BY c.family_id, c.counterpart_person_id)
                     FROM private.relation_structural_candidates(ic.interpretation_key) c), '[]'::jsonb) AS candidates
    FROM private.interpretation_current ic
    JOIN private.interpretation_party_current pc
      ON pc.interpretation_key=ic.interpretation_key AND pc.party_role='principal'
   WHERE ic.predicate='relation.parent' AND ic.status='proposed' AND ic.source_id=:source::bigint
) t;
ROLLBACK;
