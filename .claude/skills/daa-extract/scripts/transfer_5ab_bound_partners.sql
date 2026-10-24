-- Ægteskabsarkenes S-svar, som de blev bundet i en base (svaroverførslen, transfer_answers.py --old-bound): pr. ægteskab
-- den person, ægtefællepersonaen blev accepteret som ved arkets afgørelse. Det gamle forslag kan ikke altid genberegnes
-- med nuværende kode fra de gamle rækker (#244: et forkert ægteskabsnummer giver i dag U/nummer_modsiger_bog, så S'et
-- ville pege på »ingen«); hændelsen bærer den person, projektejerens svar faktisk gav. Læse-kun; ingen CREATE.
-- Udskrift: linjer »<interpretation_key>|<person-id>«, sorteret COLLATE "C". Nøglerne er uuid'er: kalderen skriver dem til
-- en 0600-fil, aldrig til terminalen.
-- Brug: psql -At -v src=<kilde> -v sheet_sha256=<64 hex> -f transfer_5ab_bound_partners.sql > <fil>
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
SELECT pc.interpretation_key::text || '|' || e.canonical_person_id::text
  FROM (SELECT DISTINCT ON (ev.source_persona_id) ev.*
          FROM private.source_persona_identity_event ev
          JOIN private.source_persona sp ON sp.id=ev.source_persona_id AND sp.source_id=:src
         WHERE ev.evidence->>'sheet_sha256'=:'sheet_sha256'
         ORDER BY ev.source_persona_id, ev.version DESC) e
  JOIN private.interpretation_party_current pc ON pc.source_persona_id=e.source_persona_id AND pc.party_role='spouse'
 WHERE e.decision_status='accepted'
 ORDER BY pc.interpretation_key::text COLLATE "C";
COMMIT;
