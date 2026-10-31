-- Trin 6b (plan Task 10/15): negativkontrollens syntetiske samme_som-par [forkert person, facit] (mindste id først) fra
-- hovedkørslernes kontrafaktiske par. Output rummer person-id'er: skriv til en 0600-fil under ~/.private/.
-- Facit, klynge og kontrafaktiske par er defineret som i calibrate-publication-control.sql.
-- Brug: psql -X -q -At -d <base> -v source_id=<n> -v input_sha256=<hovedinput> [-v facit=…] -f … > par.json
\set ON_ERROR_STOP on
\if :{?facit}
\else
  \set facit 'authority:person_external_id'
\endif
SET default_transaction_read_only=on;
WITH RECURSIVE
hoved AS (
  SELECT r.id, r.input_spec FROM private.source_persona_identity_candidate_run r
   WHERE r.source_id=:source_id AND r.input_sha256=:'input_sha256' AND jsonb_typeof(r.config->'controlMargin')='number'),
truth AS (
  SELECT i.source_persona_id AS pid, i.canonical_person_id AS facit
    FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
   WHERE :'facit' LIKE 'authority:%' AND p.source_id=:source_id AND i.decision_status='accepted'
     AND i.canonical_person_id IS NOT NULL AND i.evidence->>'authority'=substr(:'facit',11)
  UNION ALL
  SELECT p.id, b.person_id
    FROM private.source_persona p CROSS JOIN LATERAL private.publication_persona_binding(p.id) b
    JOIN public.person q ON q.id=b.person_id
   WHERE :'facit'='binding' AND p.source_id=:source_id AND b.binding_status='published' AND NOT coalesce(q.staged,false)),
edge AS (
  SELECT r.subjekt_id AS a, r.objekt_id AS b FROM public.relation r
   WHERE r.rolle='samme_som' AND r.subjekt_type='person' AND r.objekt_type='person'
  UNION
  SELECT r.objekt_id, r.subjekt_id FROM public.relation r
   WHERE r.rolle='samme_som' AND r.subjekt_type='person' AND r.objekt_type='person'),
klynge(facit, person) AS (
  SELECT DISTINCT t.facit, t.facit FROM truth t
  UNION
  SELECT k.facit, e.b FROM klynge k JOIN edge e ON e.a=k.person),
kf AS (
  SELECT DISTINCT t.facit, (e->>'person_id')::bigint AS w
    FROM hoved h JOIN private.source_persona_identity_candidate c ON c.run_id=h.id
    JOIN truth t ON t.pid=c.source_persona_id
    CROSS JOIN LATERAL jsonb_array_elements(c.basis->'member_scores') e
   WHERE NOT EXISTS (SELECT 1 FROM klynge k WHERE k.facit=t.facit AND k.person=(e->>'person_id')::bigint))
SELECT coalesce(jsonb_agg(jsonb_build_array(least(w,facit),greatest(w,facit))
                          ORDER BY least(w,facit),greatest(w,facit)),'[]'::jsonb)
  FROM (SELECT DISTINCT w, facit FROM kf) x;
