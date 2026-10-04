-- Driftsbaseline (spec 2026-10-03 §4.3). Læse-kun. Indholdshash over de data, klassifikationen og
-- målfindingen hviler på (assertion, fact, person, identitet, placering, promotion-regler og rækketal for
-- conclusion, narrative, relation og family_member = »counts«-rækken), klausulsættet og skemaet. Driftssammenligningen er PR. FELT over
-- canonical_sha256, clause_set_sha256 og schema_sha256. n_interpretations_src er et TILSTANDSFELT
-- (antal distinkte forslag; 0 i dump-tilstand), ikke en driftsinvariant: ingest ændrer det lovligt, en
-- afgørelse tilføjer en version men ikke et forslag. Ingen tællinger af autorisationer eller writer-profiler.
-- Input: psql-variablen src. Output: daa.transfer_baseline.
-- Pinner sessionsindstillinger (TimeZone, extra_float_digits, IntervalStyle, DateStyle, search_path, row_security) under beregningen,
-- så hashen er ens lokalt og i prod (Supabase = UTC), og gendanner kalderens værdier bagefter. search_path=pg_catalog:
-- alle objekter i filen er skemakvalificerede (public./private./extensions.).
SELECT set_config('daa._saved_tz', current_setting('TimeZone'), false), set_config('daa._saved_efd', current_setting('extra_float_digits'), false),
       set_config('daa._saved_is', current_setting('IntervalStyle'), false), set_config('daa._saved_ds', current_setting('DateStyle'), false),
       set_config('daa._saved_sp', current_setting('search_path'), false), set_config('daa._saved_rs', current_setting('row_security'), false) \g /dev/null
-- row_security=off: en rolle under RLS skal fejle, ikke filtrere lydløst.
SELECT set_config('TimeZone','UTC',false), set_config('extra_float_digits','1',false), set_config('IntervalStyle','postgres',false),
       set_config('DateStyle','ISO, MDY',false), set_config('search_path','pg_catalog',false), set_config('row_security','off',false) \g /dev/null
WITH tab AS (
  SELECT 'assertion' AS n, encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(a)::text, E'\n' ORDER BY a.id),''),'UTF8'),'sha256'),'hex') AS h FROM public.assertion a
  UNION ALL SELECT 'fact', encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(f)::text, E'\n' ORDER BY f.id),''),'UTF8'),'sha256'),'hex') FROM public.fact f
  UNION ALL SELECT 'person', encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(p)::text, E'\n' ORDER BY p.id),''),'UTF8'),'sha256'),'hex') FROM public.person p
  UNION ALL SELECT 'identity', encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(s)::text, E'\n' ORDER BY s.source_persona_id, s.version),''),'UTF8'),'sha256'),'hex') FROM private.source_persona_identity s
  UNION ALL SELECT 'placement', encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(pl)::text, E'\n' ORDER BY pl.id, pl.version),''),'UTF8'),'sha256'),'hex') FROM private.source_persona_placement_current pl
  UNION ALL SELECT 'promotion_rule', encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(r)::text, E'\n' ORDER BY r.rule_key COLLATE "C", r.rule_version),''),'UTF8'),'sha256'),'hex') FROM private.interpretation_promotion_rule r
  UNION ALL SELECT 'counts', md5(concat_ws('|',
      (SELECT count(*) FROM public.conclusion), (SELECT count(*) FROM public.narrative),
      (SELECT count(*) FROM public.relation), (SELECT count(*) FROM public.family_member)))
), parents AS (
  SELECT sr.record_key, so.parent_observation_id AS parent, max(coalesce(so.clause_set_seq,1)) AS seq
    FROM private.source_observation so
    JOIN private.source_record_anchor_current ac ON ac.occurrence_id = so.occurrence_id AND ac.decision_status = 'accepted'
    JOIN private.source_record sr ON sr.id = ac.source_record_id
   WHERE so.observation_kind = 'clause' AND sr.source_id = :src
   GROUP BY sr.record_key, so.parent_observation_id
), recs AS (
  SELECT sr.record_key, p.seq, coalesce(private.clause_set_sha256(p.parent, p.seq), 'none') AS h
    FROM private.source_record sr LEFT JOIN parents p ON p.record_key = sr.record_key
   WHERE sr.source_id = :src
), sch AS (
  SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' ||
         md5(pg_get_functiondef(p.oid)) AS t
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','private') AND p.prokind IN ('f','p')
  UNION ALL
  SELECT n.nspname || '.' || c.relname || '.' || a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' ||
         CASE WHEN a.attnotnull THEN 'NO' ELSE 'YES' END
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p','v','m','f') AND a.attnum > 0 AND NOT a.attisdropped
), b AS (
  SELECT
    encode(extensions.digest(convert_to((SELECT string_agg(n || '=' || h, E'\n' ORDER BY n COLLATE "C") FROM tab),'UTF8'),'sha256'),'hex') AS canonical_sha256,
    encode(extensions.digest(convert_to(coalesce((SELECT string_agg(record_key || '|' || coalesce(seq::text,'none') || '|' || h, E'\n' ORDER BY record_key COLLATE "C") FROM recs),''),'UTF8'),'sha256'),'hex') AS clause_set_sha256,
    (SELECT count(DISTINCT interpretation_key) FROM private.interpretation WHERE source_id = :src) AS n_interpretations_src,
    encode(extensions.digest(convert_to((SELECT string_agg(t, E'\n' ORDER BY t COLLATE "C") FROM sch),'UTF8'),'sha256'),'hex') AS schema_sha256
)
SELECT set_config('daa.transfer_baseline', to_jsonb(b)::text, false) AS transfer_baseline FROM b;
SELECT set_config('TimeZone', current_setting('daa._saved_tz'), false), set_config('extra_float_digits', current_setting('daa._saved_efd'), false),
       set_config('IntervalStyle', current_setting('daa._saved_is'), false), set_config('DateStyle', current_setting('daa._saved_ds'), false),
       set_config('search_path', current_setting('daa._saved_sp'), false), set_config('row_security', current_setting('daa._saved_rs'), false) \g /dev/null
