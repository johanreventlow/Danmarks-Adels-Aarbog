-- Opfølgning på dubletreglen (decisions 2026-10-25 og 2026-10-26): det ene ægteskab fra GO 2, hvor kontrolarkets
-- svar `731=753` efter den gamle regel bandt ægtefællen til post 731 (familie 179) i stedet for familiens post 753
-- (familie 202 med hovedpersonen 294). Læsemåling: `DUBLET_GO2 fase=<foer|efter|ukendt>` og en linje med antal.
-- Brug (læsetransaktion): psql -X -At -v ON_ERROR_STOP=1 -v src=1 -f fix_go2_dublet_maal.sql
\set QUIET on
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15min';
WITH sp AS (
  SELECT i.source_persona_id, i.canonical_person_id, i.version, i.evidence
    FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
   WHERE p.source_id=:src AND i.decision_status='accepted'
     AND EXISTS (SELECT 1 FROM private.source_persona_identity_event e WHERE e.source_persona_id=i.source_persona_id
                  AND e.evidence->'same_individual_person_ids' @> '[731,753]'::jsonb)),
aeg AS (
  SELECT ic.id, ic.status FROM private.interpretation_current ic
    JOIN private.interpretation_party_current pc ON pc.interpretation_key=ic.interpretation_key AND pc.party_role='spouse'
   WHERE pc.source_persona_id IN (SELECT source_persona_id FROM sp) AND ic.predicate='relation.marriage'),
x AS (
  SELECT (SELECT count(*) FROM sp) personas, (SELECT min(canonical_person_id) FROM sp) person, (SELECT min(version) FROM sp) version,
         (SELECT count(*) FROM aeg) aegteskaber, (SELECT min(status) FROM aeg) status,
         (SELECT count(*) FROM aeg JOIN private.interpretation_promotion pr ON pr.interpretation_id=aeg.id
           WHERE pr.target_type='family' AND pr.target_id=202) promoveret_202,
         (SELECT array_agg(person_id ORDER BY person_id) FROM family_member WHERE family_id=202 AND rolle='partner')::text fam202,
         (SELECT array_agg(person_id ORDER BY person_id) FROM family_member WHERE family_id=179 AND rolle='partner')::text fam179)
SELECT format('personas=%s person=%s version=%s aegteskaber=%s status=%s promoveret_202=%s fam202=%s fam179=%s',
              personas, person, version, aegteskaber, status, promoveret_202, fam202, fam179)
       ||E'\nDUBLET_GO2 fase='||CASE
         WHEN personas=1 AND person=731 AND version=1 AND aegteskaber=1 AND status='proposed' AND promoveret_202=0
              AND fam202='{294,753}' AND fam179='{261,731}' THEN 'foer'
         WHEN personas=1 AND person=753 AND version=2 AND aegteskaber=1 AND status='accepted' AND promoveret_202=1
              AND fam202='{294,753}' AND fam179='{261,731}' THEN 'efter'
         ELSE 'ukendt' END
FROM x;
COMMIT;
