-- Laese-kun klausul-projektion, anon-delen (spec 4.1.6 anon-hashes, issue 195).
-- Koeres af driveren under SET LOCAL ROLE anon i samme transaktion som ejer-delen.
-- Hasher hele raekker, som anon ser dem gennem RLS. Returnerer kolonnen anon_sha256.
WITH guard AS (
  SELECT CASE
    WHEN current_user <> 'anon'
      THEN ('CLAUSE_PROJECTION_NOT_ANON:' || current_user)::int
    WHEN current_setting('transaction_read_only') <> 'on'
      THEN ('CLAUSE_PROJECTION_NOT_READ_ONLY:' || current_setting('transaction_read_only'))::int
    WHEN current_setting('transaction_isolation') <> 'repeatable read'
      THEN ('CLAUSE_PROJECTION_NOT_REPEATABLE_READ:' || current_setting('transaction_isolation'))::int
    ELSE 1
  END AS ok
)
SELECT jsonb_build_object(
  'assertion', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.assertion x),
  'citation', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.citation x),
  'conclusion', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.conclusion x),
  'fact', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.fact x),
  'family_member', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.family_member x),
  'narrative', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.narrative x),
  'person', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.person x),
  'person_external_id', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.person_external_id x)
)::text AS anon_sha256
FROM guard
WHERE ok = 1
