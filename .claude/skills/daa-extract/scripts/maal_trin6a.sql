-- Læse-kun måling til trin 6a's ceremonier A og B (runbook docs/runbooks/trin6a-prod.md): kun antal, ingen tekst.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -f maal_trin6a.sql
-- To linjer; den sidste er tilstandslinjen:
--   T6A_FLAG k3 <klassifikation:antal,…> | <flag:antal,…>   (1939's klausuler pr. klassifikation og pr. flag)
--   T6A_MAAL funktioner=<0-12> profiler=<0-2> view=<t|f> k3_klausuler=<n> k3_poster=<n> k3_afventer=<n>
--     k3_flagget=<n> k3_batch=<n> k1_klausuler=<n> k1_poster=<n> k1_hash=<md5>
--   funktioner   af de 12 funktioner, ceremoni A opretter (private.* og public.red_apply_reimport_source_text_revision)
--   profiler     af de to writer-profiler, ceremoni A seeder (1939-klausuler, 2018-20-kildetekst-revision)
--   view         private.clause_observation_current har kolonnen parent_text_id
--   k3_*         1939 (kilde 3): klausuler, distinkte helposter med klausuler, dispositionerne afventer_fortolkning og
--                maskinelt_flagget, og finaliserede batches med profilen daa-1939-clause-evidence-v1
--   k1_*         2018-20 (kilde 1): klausuler, distinkte helposter og en hash over hver klausuls id, sæt, spænd,
--                teksthash og gældende disposition — skal være uændret af begge ceremonier
-- Tilstande: foer (funktioner=0 profiler=0 view=f k3_*=0), a (funktioner=12 profiler=2 view=t k3_*=0),
-- b (som a, men k3_klausuler=954 k3_poster=584 k3_afventer=719 k3_flagget=235 k3_batch=1).
\set QUIET on
\set ON_ERROR_STOP on
BEGIN READ ONLY;
WITH k3 AS (
  SELECT c.clause_classification, c.clause_flags
    FROM private.source_observation c
    JOIN private.source_record_occurrence o ON o.id=c.occurrence_id
    JOIN private.source_rendition r ON r.id=o.rendition_id
   WHERE c.observation_kind='clause' AND r.source_id=3
)
SELECT 'T6A_FLAG k3 '||
       coalesce((SELECT string_agg(k||':'||n,',' ORDER BY k COLLATE "C")
                   FROM (SELECT coalesce(clause_classification,'-') k, count(*) n FROM k3 GROUP BY 1) a),'-')||' | '||
       coalesce((SELECT string_agg(k||':'||n,',' ORDER BY k COLLATE "C")
                   FROM (SELECT f k, count(*) n FROM k3, jsonb_array_elements_text(coalesce(clause_flags,'[]'::jsonb)) f
                          GROUP BY 1) b),'-');
WITH fn AS (
  SELECT count(*) AS n FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
   WHERE (s.nspname,p.proname) IN (
     ('private','clause_write_set'),('private','helpost_text_current'),
     ('private','interpretation_proposal_key_material_v2'),('private','record_helpost_observation'),
     ('private','record_helpost_status'),('private','supersede_for_text_revision'),
     ('private','text_revision_binding_set'),('private','text_revision_dependents'),
     ('private','write_source_text_revision'),('private','writer_config_helpost_kind'),
     ('private','writer_config_text_form'),('public','red_apply_reimport_source_text_revision'))
     -- clause_write_set findes også før 6a (4 argumenter); kun 5-argumentsudgaven tæller.
     AND NOT (p.proname='clause_write_set' AND p.pronargs<>5)
), prof AS (
  SELECT count(*) AS n FROM private.reimport_writer_profile
   WHERE profile_id IN ('daa-1939-clause-evidence-v1','daa-2018-20-source-text-revision-v1')
), v AS (
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='private'
                    AND table_name='clause_observation_current' AND column_name='parent_text_id') AS ok
), kl AS (
  SELECT r.source_id, count(*) AS n, count(DISTINCT c.parent_observation_id) AS poster,
         count(*) FILTER (WHERE d.disposition::text='afventer_fortolkning') AS afventer,
         count(*) FILTER (WHERE d.disposition::text='maskinelt_flagget') AS flagget
    FROM private.source_observation c
    JOIN private.source_record_occurrence o ON o.id=c.occurrence_id
    JOIN private.source_rendition r ON r.id=o.rendition_id
    LEFT JOIN private.clause_disposition_current d ON d.observation_id=c.id
   WHERE c.observation_kind='clause' AND r.source_id IN (1,3)
   GROUP BY r.source_id
), k1h AS (
  SELECT md5(coalesce(string_agg(concat_ws(':',c.id,c.clause_set_seq,c.char_from,c.char_to,
           md5(c.verbatim_text),d.disposition),'|' ORDER BY c.id),'')) AS h
    FROM private.source_observation c
    JOIN private.source_record_occurrence o ON o.id=c.occurrence_id
    JOIN private.source_rendition r ON r.id=o.rendition_id
    LEFT JOIN private.clause_disposition_current d ON d.observation_id=c.id
   WHERE c.observation_kind='clause' AND r.source_id=1
), b AS (
  SELECT count(*) AS n FROM private.reimport_batch
   WHERE source_id=3 AND profile_id='daa-1939-clause-evidence-v1' AND status='finalized'
)
SELECT format('T6A_MAAL funktioner=%s profiler=%s view=%s k3_klausuler=%s k3_poster=%s k3_afventer=%s k3_flagget=%s '
              'k3_batch=%s k1_klausuler=%s k1_poster=%s k1_hash=%s',
              fn.n, prof.n, CASE WHEN v.ok THEN 't' ELSE 'f' END,
              coalesce(k3.n,0), coalesce(k3.poster,0), coalesce(k3.afventer,0), coalesce(k3.flagget,0), b.n,
              coalesce(k1.n,0), coalesce(k1.poster,0), k1h.h)
  FROM fn, prof, v, b, k1h
  LEFT JOIN kl k3 ON k3.source_id=3
  LEFT JOIN kl k1 ON k1.source_id=1;
ROLLBACK;
