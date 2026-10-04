-- Driftsbaseline (spec 2026-10-03 §4.3). Læse-kun. Indholdshash over de data, klassifikationen og
-- målfindingen hviler på, antal i de øvrige kanoniske tabeller, klausulsættet og skemaet.
-- Ingen tællinger af autorisationer, writer-profiler eller fortolkninger: dry-run og ingest
-- ændrer dem lovligt. n_interpretations_src tæller forslag (distinkte nøgler), ikke versioner: en afgørelse tilføjer en version. Input: psql-variablen src. Output: daa.transfer_baseline.
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
  SELECT c.table_schema || '.' || c.table_name || '.' || c.column_name || ':' || c.data_type || ':' || c.is_nullable
    FROM information_schema.columns c WHERE c.table_schema IN ('public','private')
), b AS (
  SELECT
    encode(extensions.digest(convert_to((SELECT string_agg(n || '=' || h, E'\n' ORDER BY n COLLATE "C") FROM tab),'UTF8'),'sha256'),'hex') AS canonical_sha256,
    encode(extensions.digest(convert_to(coalesce((SELECT string_agg(record_key || '|' || coalesce(seq::text,'none') || '|' || h, E'\n' ORDER BY record_key COLLATE "C") FROM recs),''),'UTF8'),'sha256'),'hex') AS clause_set_sha256,
    (SELECT count(DISTINCT interpretation_key) FROM private.interpretation WHERE source_id = :src) AS n_interpretations_src,
    encode(extensions.digest(convert_to((SELECT string_agg(t, E'\n' ORDER BY t COLLATE "C") FROM sch),'UTF8'),'sha256'),'hex') AS schema_sha256
)
SELECT set_config('daa.transfer_baseline', to_jsonb(b)::text, false) AS transfer_baseline FROM b;
