-- Trin 6b (plan Task 10/15): kalibreringens facit som JSON [{source_persona_id, canonical_person_id}] (samme form som
-- export-truth.sql). Output rummer id'er: skriv til en 0600-fil under ~/.private/, læs den aldrig i en agent.
-- Brug: psql -X -q -At -d <base> -v source_id=<n> [-v facit=authority:person_external_id|binding] -f … > facit.json
--   authority:<a>  accepterede identiteter for kilden med evidence.authority = <a> og canonical_person_id sat
--                  (standard authority:person_external_id = 149b's faste kobling; for kilde 1 de 587 kendte);
--   binding        personas for kilden med en publiceret narrativbinding; facit = bindingens person, undtagen staged
--                  personer (spec §4.3: kontrolmængden er de ikke-staged).
-- Samme definition som truth-CTE'en i calibrate-publication-control.sql og calibration-negative-pairs.sql.
\set ON_ERROR_STOP on
\if :{?facit}
\else
  \set facit 'authority:person_external_id'
\endif
SET default_transaction_read_only=on;
SELECT set_config('cal.facit', :'facit', false) IS NOT NULL AS ok \g /dev/null
DO $$ BEGIN
  IF current_setting('cal.facit') !~ '^(authority:[a-z_]+|binding)$' THEN RAISE EXCEPTION 'CALIBRATION_FACIT_INVALID'; END IF;
END $$;
WITH truth AS (
  SELECT i.source_persona_id AS pid, i.canonical_person_id AS facit
    FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
   WHERE :'facit' LIKE 'authority:%' AND p.source_id=:source_id AND i.decision_status='accepted'
     AND i.canonical_person_id IS NOT NULL AND i.evidence->>'authority'=substr(:'facit',11)
  UNION ALL
  SELECT p.id, b.person_id
    FROM private.source_persona p CROSS JOIN LATERAL private.publication_persona_binding(p.id) b
    JOIN public.person q ON q.id=b.person_id
   WHERE :'facit'='binding' AND p.source_id=:source_id AND b.binding_status='published' AND NOT coalesce(q.staged,false))
SELECT coalesce(jsonb_agg(jsonb_build_object('source_persona_id',t.pid::text,'canonical_person_id',t.facit)
       ORDER BY t.pid),'[]'::jsonb)
  FROM truth t;
