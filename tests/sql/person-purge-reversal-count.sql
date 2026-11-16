-- Task 7 / R30: samme funktion som previewet; kun tal i normalt output.
\set ON_ERROR_STOP on
\set QUIET on
WITH plan AS MATERIALIZED (SELECT * FROM private.person_purge_plan((:pid)::bigint)),
q3 AS MATERIALIZED (SELECT * FROM private.person_purge_fortrydelse((:pid)::bigint,
  coalesce((SELECT jsonb_agg(to_jsonb(plan)) FROM plan),'[]'::jsonb))),
generic_ready AS (SELECT batch_id AS id FROM q3 WHERE vej='red_reverse_reimport'),
generic_lost AS (SELECT batch_id AS id FROM q3 WHERE vej='red_reverse_reimport' AND niveau IS NOT NULL),
publication_ready AS (SELECT batch_id AS id FROM q3 WHERE vej='red_reverse_reimport_publication'),
publication_lost AS (SELECT batch_id AS id FROM q3 WHERE vej='red_reverse_reimport_publication' AND niveau IS NOT NULL)

SELECT (SELECT count(*) FROM generic_ready) AS reimport_kan_nu,
       (SELECT count(*) FROM generic_lost) AS reimport_mistes,
       (SELECT count(*) FROM generic_ready) AS wrapper_kan_nu,
       (SELECT count(*) FROM generic_lost) AS wrapper_mistes,
       0::bigint AS cases_kan_nu, 0::bigint AS cases_mistes,
       (SELECT count(*) FROM publication_ready) AS publication_kan_nu,
       (SELECT count(*) FROM publication_lost) AS publication_mistes
       ,(SELECT count(*) FROM q3 WHERE niveau='advarsel') AS advarsler
       ,(SELECT count(*) FROM q3 WHERE niveau='note') AS noter
-- Testen forbruger PRÆCIS samme funktion og asserterer både antal og batchmængder.
-- UUID'er sendes kun til sessionsvariabler, aldrig til almindeligt måleoutput.
\if :{?purge_reversal_assert}
       ,jsonb_build_object(
         'generic_ready',coalesce((SELECT jsonb_agg(id ORDER BY id) FROM generic_ready),'[]'::jsonb),
         'generic_lost',coalesce((SELECT jsonb_agg(id ORDER BY id) FROM generic_lost),'[]'::jsonb),
         'publication_ready',coalesce((SELECT jsonb_agg(id ORDER BY id) FROM publication_ready),'[]'::jsonb),
         'publication_lost',coalesce((SELECT jsonb_agg(id ORDER BY id) FROM publication_lost),'[]'::jsonb)) AS batches
\gset reversal_
\else
;
\endif
