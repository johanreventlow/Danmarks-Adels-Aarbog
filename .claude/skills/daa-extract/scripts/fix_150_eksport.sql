-- #150 trin 5c-1: legacy-placering for én kilde som JSON til build_header_manifest.py (--legacy-json).
-- Kun koder og tal (ingen navne): stamtavle-schemaets entry-koder i trykt orden + person_external_id-rækkerne.
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
             FROM public.person_external_id pe WHERE pe.source_id=:src))::text;
ROLLBACK;
