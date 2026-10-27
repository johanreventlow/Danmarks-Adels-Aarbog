-- #150 trin 5c-1: legacy-placering for én kilde som JSON til build_header_manifest.py (--legacy-json).
-- Kun koder og tal (ingen navne): stamtavle-schemaets entry-koder i trykt orden, person_external_id-rækkerne og
-- forælder-barn-par (family_member) mellem to af kildens poster, som record_keys (manifestets krydscheck).
-- Brug (læsetransaktion): psql -X -At -v ON_ERROR_STOP=1 -v src=1 -f fix_150_eksport.sql > ~/.private/5c/legacy.json
\set QUIET on
BEGIN READ ONLY;
SELECT jsonb_build_object(
  'entries', (SELECT coalesce(jsonb_agg(e.code ORDER BY e.sort_order), '[]'::jsonb)
                FROM public.lineage_scheme s JOIN public.lineage_scheme_entry e ON e.scheme_id=s.id
               WHERE s.source_id=:src AND s.kind='stamtavle'),
  'rows', (SELECT coalesce(jsonb_agg(jsonb_build_object(
              'record_key', pe.record_key, 'linje', pe.linje, 'nr', pe.nr, 'slaegtled_lokal', pe.slaegtled_lokal,
              'slaegtled_gennem', pe.slaegtled_gennem, 'kuld', pe.kuld) ORDER BY pe.record_key), '[]'::jsonb)
             FROM public.person_external_id pe WHERE pe.source_id=:src),
  'parents', (SELECT coalesce(jsonb_agg(DISTINCT jsonb_build_object('child', c.record_key, 'parent', p.record_key)), '[]'::jsonb)
                FROM public.family_member b
                JOIN public.family_member pa ON pa.family_id=b.family_id AND pa.rolle='partner'
                JOIN public.person_external_id c ON c.person_id=b.person_id AND c.source_id=:src AND c.record_key IS NOT NULL
                JOIN public.person_external_id p ON p.person_id=pa.person_id AND p.source_id=:src AND p.record_key IS NOT NULL
               WHERE b.rolle='barn'))::text;
ROLLBACK;
