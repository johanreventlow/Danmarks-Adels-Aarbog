-- #240 (decisions 2026-10-26): læsemåling af de 5 par, der hver står i to familier. Kun id'er, antal og ja/nej.
-- Udskriver nøgle=værdi-linjer og til sidst `MAAL_240 fase=<pre|samlet|bundet|ukendt> sha=<sha256>`, hvor sha'en er
-- over alle linjerne. Fasen afgør, hvilken sha prod skal give (fastlagt ved prøvekørslen på en kopi af prod).
-- Brug (læsetransaktion): psql -X -At -v ON_ERROR_STOP=1 -v actor=<redaktør-uuid> -v src=1 -f fix_240_maal.sql
\set QUIET on
BEGIN READ ONLY;
SELECT set_config('request.jwt.claim.sub', :'actor', true) \g /dev/null
WITH m240_par(n, fuld, tom, a, b) AS (
  VALUES (1,188::bigint,11::bigint,16::bigint,278::bigint),(2,282,256,373,425),(3,354,363,544,560),(4,361,371,558,575),(5,377,372,577,587)),
m240_linjer(nr, linje) AS (
SELECT 100+n, format('par%s fuld=%s partnere=%s boern=%s vielser=%s paastande=%s citater=%s noter=%s', n, fuld,
  (SELECT string_agg(person_id||':'||coalesce(ordinal::text,'-'),',' ORDER BY person_id) FROM family_member WHERE family_id=fuld AND rolle='partner'),
  (SELECT count(*) FROM family_member WHERE family_id=fuld AND rolle<>'partner'),
  (SELECT count(*) FROM fact WHERE subjekt_type='family' AND subjekt_id=fuld AND faktatype='vielse'),
  (SELECT count(*) FROM fact f JOIN assertion x ON x.target_type='fact' AND x.target_id=f.id WHERE f.subjekt_type='family' AND f.subjekt_id=fuld),
  (SELECT count(*) FROM fact f JOIN assertion x ON x.target_type='fact' AND x.target_id=f.id JOIN citation c ON c.assertion_id=x.id
    WHERE f.subjekt_type='family' AND f.subjekt_id=fuld),
  (SELECT count(*) FROM note WHERE target_type='family' AND target_id=fuld))
FROM m240_par
UNION ALL
SELECT 200+n, format('par%s tom=%s findes=%s medlemmer=%s fakta=%s noter=%s', n, tom,
  EXISTS (SELECT 1 FROM family WHERE id=tom),
  (SELECT count(*) FROM family_member WHERE family_id=tom),
  (SELECT count(*) FROM fact WHERE subjekt_type='family' AND subjekt_id=tom),
  (SELECT count(*) FROM note WHERE target_type='family' AND target_id=tom))
FROM m240_par
UNION ALL
SELECT 300, 'dobbeltpar_i_traeet='||(SELECT count(*) FROM (
  SELECT p FROM (SELECT family_id, array_agg(person_id ORDER BY person_id) p FROM family_member WHERE rolle='partner'
                 GROUP BY 1 HAVING count(*)=2) s GROUP BY p HAVING count(*)>1) d)
UNION ALL
SELECT 400+n, format('par%s aegteskaber=%s proposed=%s accepted=%s bindbare=%s promoveret_til_fuld=%s', n,
  count(*), count(*) FILTER (WHERE ic.status='proposed'), count(*) FILTER (WHERE ic.status='accepted'),
  count(*) FILTER (WHERE private.relation_binding_state(ic.id) IS NOT NULL),
  count(*) FILTER (WHERE EXISTS (SELECT 1 FROM private.interpretation_promotion pr
                                 WHERE pr.interpretation_id=ic.id AND pr.target_type='family' AND pr.target_id=m240_par.fuld)))
FROM m240_par
JOIN LATERAL (
  SELECT DISTINCT ic.id, ic.status FROM private.interpretation_current ic
  JOIN private.interpretation_party_current p1 ON p1.interpretation_key=ic.interpretation_key
  JOIN private.source_persona_identity i1 ON i1.source_persona_id=p1.source_persona_id AND i1.decision_status='accepted'
  JOIN private.interpretation_party_current p2 ON p2.interpretation_key=ic.interpretation_key AND p2.party_role<>p1.party_role
  JOIN private.source_persona_identity i2 ON i2.source_persona_id=p2.source_persona_id AND i2.decision_status='accepted'
  WHERE ic.source_id=:src AND ic.predicate='relation.marriage'
    AND (i1.canonical_person_id,i2.canonical_person_id)=(m240_par.a,m240_par.b)) ic ON true
GROUP BY n
UNION ALL
SELECT 500, 'beslutningsmaengde='||jsonb_array_length(coalesce(private.relation_decision_set(:src)->'items','[]'::jsonb))
UNION ALL
SELECT 600, 'kontrolstatus='||coalesce((SELECT string_agg(s.status||'/'||s.reason, ',' ORDER BY r.id)
  FROM private.identity_control_run r, private.control_run_status(r.id) s WHERE r.source_id=:src),'ingen'))
SELECT linje FROM (SELECT nr, linje FROM m240_linjer
UNION ALL
SELECT 999, 'MAAL_240 fase='||CASE
    WHEN (SELECT count(*) FROM family WHERE id IN (11,256,363,371,372))=5
     AND (SELECT count(*) FROM family_member WHERE family_id IN (11,256,363,371,372) AND rolle<>'partner')=0 THEN 'pre'
    WHEN (SELECT count(*) FROM family WHERE id IN (11,256,363,371,372))=0
     AND NOT EXISTS (SELECT 1 FROM m240_linjer WHERE nr BETWEEN 401 AND 405 AND linje !~ 'accepted=0 ') THEN 'samlet'
    WHEN (SELECT count(*) FROM family WHERE id IN (11,256,363,371,372))=0
     AND NOT EXISTS (SELECT 1 FROM m240_linjer WHERE nr BETWEEN 401 AND 405 AND linje !~ 'proposed=0 ') THEN 'bundet'
    ELSE 'ukendt' END
  ||' sha='||encode(sha256(convert_to(string_agg(linje, E'\n' ORDER BY nr), 'UTF8')), 'hex')
FROM m240_linjer) ud ORDER BY nr;
COMMIT;
