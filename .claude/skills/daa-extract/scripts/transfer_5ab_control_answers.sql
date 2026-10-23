-- Kontrolarkets svar, som de står skrevet i en base (plan B2 Task 1): kilden til forudfyldning af nye linjer i 2b-i-arket
-- og køen (transfer_answers.py --prefill-answers). Ét svar pr. persona i kilden: den seneste identitetshændelse, hvis
-- evidens bærer kontrolarkets hash. Rækkefilen kan ikke bruges, fordi den kun bærer kandidat-id'er; hændelsen bærer den
-- person, projektejerens svar faktisk gav. Læse-kun; ingen CREATE.
-- Udskrift: linjer »<persona-uuid>|<accepted|rejected|unresolved>|<person-id eller tom>|<grund eller tom>«, sorteret
-- COLLATE "C". Linjerne bærer uuid'er: kalderen skriver dem til en 0600-fil, aldrig til terminalen.
-- Brug: psql -At -v src=<kilde> -v sheet_sha256=<64 hex> -f transfer_5ab_control_answers.sql > <fil>
\set ON_ERROR_STOP on
\if :{?src}
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_USAGE: -v src mangler'; END $$;
\endif
\if :{?sheet_sha256}
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_USAGE: -v sheet_sha256 mangler'; END $$;
\endif
BEGIN READ ONLY;
SET LOCAL search_path TO pg_catalog;
SET LOCAL TimeZone='UTC';
SET LOCAL row_security=off;
SELECT :'sheet_sha256' ~ '^[0-9a-f]{64}$' AS t5_hex \gset
\if :t5_hex
\else
DO $$ BEGIN RAISE EXCEPTION 'STEP_USAGE: sheet_sha256 skal være 64 hex'; END $$;
\endif
SELECT e.source_persona_id::text || '|' || e.decision_status || '|' ||
       CASE WHEN e.decision_status='accepted' THEN e.canonical_person_id::text ELSE '' END || '|' ||
       coalesce(e.evidence->>'reason', '')
  FROM (SELECT DISTINCT ON (ev.source_persona_id) ev.*
          FROM private.source_persona_identity_event ev
          JOIN private.source_persona sp ON sp.id=ev.source_persona_id AND sp.source_id=:src
         WHERE ev.evidence->>'sheet_sha256'=:'sheet_sha256'
         ORDER BY ev.source_persona_id, ev.version DESC) e
 ORDER BY e.source_persona_id::text COLLATE "C";
COMMIT;
