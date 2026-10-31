-- Trin 6b (plan Task 10 Step 5): person-id'erne med publiceret narrativbinding på en kildes records (for kilde 3 de
-- 563), som JSON-array. Output rummer id'er: skriv til en 0600-fil under ~/.private/.
-- Brug: psql -X -q -At -d <base> -v source_id=<n> -f … > bundne.json
\set ON_ERROR_STOP on
SET default_transaction_read_only=on;
SELECT coalesce(jsonb_agg(DISTINCT n.subjekt_id),'[]'::jsonb)
  FROM private.narrative_record_publication b
  JOIN private.source_record r ON r.id=b.source_record_id
  JOIN public.narrative n ON n.id=b.narrative_id
 WHERE r.source_id=:source_id AND b.status='published' AND n.subjekt_type='person';
