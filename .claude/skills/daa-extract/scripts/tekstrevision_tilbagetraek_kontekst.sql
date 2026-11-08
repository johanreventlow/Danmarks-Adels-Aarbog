-- Trin 6c-3 (spec 2026-11-07-trin6c3-a6b-resten-design.md §4.4; plan Task 5): læse-kun kontekst til T/V-arkets
-- HTML-side (`tekstrevision_afstemning.py tilbagetraek-html`), som 6c-2's kort: pr. revideret post postnøglen, siderne
-- og helpostens GÆLDENDE tekst (helpost_text_current: revisionens tekst med de genfundne linjer).
-- Variabel: batch (revisionens reimport_batch.id). Ét JSON-dokument ud.
-- Rummer bogtekst om personer: skriv kun til en 0600-fil under ~/.private; læs aldrig, tæl.
-- Kørsel (ejerforbindelse): psql -X -v ON_ERROR_STOP=1 -v batch=<uuid> -f tekstrevision_tilbagetraek_kontekst.sql > kontekst.json
\set ON_ERROR_STOP on
\set QUIET on
\pset format unaligned
\pset tuples_only on
BEGIN READ ONLY;
SELECT jsonb_build_object(
  'contract','tekstrevision-tilbagetraek-kontekst-v1',
  'poster',coalesce((
    SELECT jsonb_agg(jsonb_build_object('element_id',e.element_id,'record_key',e.source_record_key,
                                        'side_fra',occ.page_from,'side_til',occ.page_to,'tekst',t.verbatim_text)
                     ORDER BY e.source_record_key COLLATE "C")
      FROM private.reimport_event e
      JOIN private.source_observation h ON h.id=(e.payload->>'parent_observation_id')::uuid
      JOIN private.source_record_occurrence occ ON occ.id=h.occurrence_id
      LEFT JOIN LATERAL private.helpost_text_current(h.id) t ON true
     WHERE e.batch_id=(:'batch')::uuid AND e.operation='source_text_revision'),'[]'::jsonb)) AS kontekst;
ROLLBACK;
