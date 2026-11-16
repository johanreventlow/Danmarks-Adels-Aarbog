-- Task 7 step 6. Kør i en redaktørsession, med -v pid=<person-id>.
-- Læser kun. Output: millisekunder, antal og blokeringsarter; ingen navne, pk'er eller tekst.
\set ON_ERROR_STOP on
\set QUIET on
WITH start AS MATERIALIZED (SELECT clock_timestamp() AS t),
preview AS MATERIALIZED (SELECT public.red_slet_person_helt_preview((:pid)::bigint) AS j FROM start)
SELECT round((extract(epoch FROM clock_timestamp()-s.t)*1000)::numeric,1) AS ms,
  (SELECT coalesce(sum(jsonb_array_length(value)),0) FROM jsonb_each(p.j->'steder')) AS raekker,
  (p.j#>>'{historik,events}')::bigint AS events,
  (p.j#>>'{historik,saet}')::bigint AS saet,
  jsonb_array_length(p.j->'advarsler') AS advarsler,
  jsonb_array_length(p.j->'til_kontrol') AS til_kontrol,
  jsonb_array_length(p.j->'storage') AS storage,
  jsonb_array_length(p.j->'blokeringer') AS blokeringer,
  ARRAY(SELECT DISTINCT b->>'art' COLLATE "C" FROM jsonb_array_elements(p.j->'blokeringer') b
    ORDER BY b->>'art' COLLATE "C") AS blokeringsarter
FROM preview p CROSS JOIN start s;
