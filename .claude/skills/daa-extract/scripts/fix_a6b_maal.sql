-- Læse-kun måling til A6b (plan 2026-10-28-a6b-noise-re-narrativer.md, Task 3): kun antal og hashes, ingen tekst.
-- Manifestet (build_narrative_revision_manifest.py) indlæses klientside; det rummer posttekst, men intet herfra
-- udskriver den.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v manifest_path=<fil> -f fix_a6b_maal.sql
-- Én linje: A6B_MAAL gammel=<n> ny=<n> ubundet=<n> andet=<n> rest=<16> maal_oevrigt=<16> events=<n> change_sets=<n>
--   change_events=<n> mentions=<16>
--   gammel/ny     manifestets bundne poster, hvis narrativtekst har manifestets gamle/nye sha256
--   ubundet       manifestets poster uden narrativpublikation (forventet: III-129)
--   andet         bundne poster med en tredje tekst (drift: ceremonien må ikke køre)
--   rest          hele narrative-rækken for alle narrativer UDEN FOR målene; skal være uændret
--   maal_oevrigt  målenes narrative-rækker uden `tekst` og `fts` (genereret af teksten); skal være uændret
--   mentions      text_mention for målene; triggeren trg_mentions_narrative genberegner dem ved revision
-- Hashes er portable (to_jsonb(x)::text, ikke x::text: locale-forskel mellem macOS og Linux).
\set QUIET on
\set ON_ERROR_STOP on
\set m `cat :'manifest_path'`
BEGIN READ ONLY;
WITH manifest AS (SELECT :'m'::jsonb AS m),
element AS (
  SELECT x->>'record_key' AS rk, x->>'old_sha256' AS old_sha, x->>'new_sha256' AS new_sha
    FROM manifest, jsonb_array_elements(m->'elements') x
),
maal AS (
  SELECT e.*, n.id AS nid, encode(sha256(convert_to(n.tekst,'UTF8')),'hex') AS cur
    FROM element e
    LEFT JOIN private.source_record sr
      ON sr.source_id=(SELECT (m->>'source_id')::bigint FROM manifest) AND sr.record_key=e.rk
    LEFT JOIN private.narrative_record_publication p ON p.source_record_id=sr.id
    LEFT JOIN public.narrative n ON n.id=p.narrative_id
)
SELECT 'A6B_MAAL'
       ||' gammel='||count(*) FILTER (WHERE nid IS NOT NULL AND cur=old_sha)
       ||' ny='||count(*) FILTER (WHERE nid IS NOT NULL AND cur=new_sha)
       ||' ubundet='||count(*) FILTER (WHERE nid IS NULL)
       ||' andet='||count(*) FILTER (WHERE nid IS NOT NULL AND cur IS DISTINCT FROM old_sha AND cur IS DISTINCT FROM new_sha)
       ||' rest='||(SELECT left(encode(sha256(convert_to(coalesce(string_agg(to_jsonb(n)::text, ',' ORDER BY n.id),''),'UTF8')),'hex'),16)
                      FROM public.narrative n
                     WHERE n.id NOT IN (SELECT nid FROM maal WHERE nid IS NOT NULL))
       ||' maal_oevrigt='||(SELECT left(encode(sha256(convert_to(coalesce(string_agg((to_jsonb(n)-'tekst'-'fts')::text, ',' ORDER BY n.id),''),'UTF8')),'hex'),16)
                              FROM public.narrative n
                             WHERE n.id IN (SELECT nid FROM maal WHERE nid IS NOT NULL))
       ||' events='||(SELECT count(*) FROM private.narrative_publication_event)
       ||' change_sets='||(SELECT count(*) FROM public.change_set)
       ||' change_events='||(SELECT count(*) FROM public.change_event)
       ||' mentions='||(SELECT left(encode(sha256(convert_to(coalesce(string_agg(to_jsonb(tm)::text, ','
                                     ORDER BY tm.kilde_id, tm.maal_type, tm.maal_id),''),'UTF8')),'hex'),16)
                          FROM public.text_mention tm
                         WHERE tm.kilde_type='narrative'
                           AND tm.kilde_id IN (SELECT nid FROM maal WHERE nid IS NOT NULL))
  FROM maal;
ROLLBACK;
