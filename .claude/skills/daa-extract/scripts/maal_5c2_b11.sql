-- Læse-kun måling til 5c-2/B11 (plan docs/superpowers/plans/2026-10-29-5c2-b11-laeserflade.md, Task 3): kun antal,
-- ingen tekst. Kører før og efter DDL'en: før giver den kun `funktioner=0`.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -f maal_5c2_b11.sql
-- Én linje: C2B11_MAAL funktioner=<0-3> [definer=<n> anon=<t|f> auth=<t|f> koord=<n> placement=<n> legacy=<n>
--   fakta=<n> bundet=<n> import=<n> ingen_kilde=<n> uden_narrativ=<n> udfald_i_alt=<n> udfald_publicering=<n>]
--   funktioner          af assertion_binding_current, public_person_facts, public_person_source_coordinates
--   definer             af de to offentlige RPC'er, der er SECURITY DEFINER
--   anon/auth           begge offentlige RPC'er kan eksekveres af rollen
--   koord               rækker fra public_person_source_coordinates (fordelt på placement/legacy)
--   fakta               rækker fra public_person_facts for alle offentlige personer (fordelt på bundet/import/ingen_kilde)
--   uden_narrativ       offentlige personer uden noget narrativ, som har mindst én fakta-række
--   udfald_i_alt        assertion-promotions på offentlige personers fakta, hvis række står uden binding
--   udfald_publicering  heraf dem, hvor betingelse 1, 2 og 4 holder, men betingelse 3 (publicering) fejler
-- RPC'erne gater selv på entitet_offentlig, så kalderens rolle ændrer ikke tallene.
\set QUIET on
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SELECT count(*) AS n FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
 WHERE (s.nspname,p.proname) IN (('private','assertion_binding_current'),('public','public_person_facts'),
                                 ('public','public_person_source_coordinates')) \gset fn_
SELECT (:fn_n=3) AS komplet \gset
\if :komplet
WITH pub AS (
  SELECT array_agg(p.id ORDER BY p.id) AS ids FROM public.person p WHERE public.entitet_offentlig('person',p.id)
), k AS (
  SELECT * FROM public.public_person_source_coordinates()
), f AS (
  SELECT * FROM public.public_person_facts((SELECT ids FROM pub))
), prom AS (
  -- Assertion-promotions på de faktarækker, RPC'en returnerer, og deres udfald.
  SELECT DISTINCT p.id,f.assertion_id,f.record_ref,
         private.assertion_binding_current(p.id) AS b14,
         (SELECT count(*) FROM private.interpretation_observation io
           WHERE io.interpretation_id=p.interpretation_id AND io.evidence_role='supporting')=1
         AND (SELECT count(*) FROM private.interpretation_observation io
                JOIN private.source_observation o ON o.id=io.observation_id
                JOIN private.source_record_anchor_current an ON an.occurrence_id=o.occurrence_id AND an.decision_status='accepted'
                JOIN private.source_record sr ON sr.id=an.source_record_id
                JOIN private.interpretation q ON q.id=p.interpretation_id
               WHERE io.interpretation_id=p.interpretation_id AND io.evidence_role='supporting'
                 AND sr.source_id=q.source_id)=1 AS b2
    FROM private.interpretation_promotion p
    JOIN f ON f.assertion_id=p.target_id
   WHERE p.target_type='assertion'
)
SELECT 'C2B11_MAAL funktioner=3'
  ||' definer='||(SELECT count(*) FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
                   WHERE s.nspname='public' AND p.proname IN ('public_person_facts','public_person_source_coordinates')
                     AND p.prosecdef)
  ||' anon='||(has_function_privilege('anon','public.public_person_facts(bigint[])','EXECUTE')
               AND has_function_privilege('anon','public.public_person_source_coordinates()','EXECUTE'))
  ||' auth='||(has_function_privilege('authenticated','public.public_person_facts(bigint[])','EXECUTE')
               AND has_function_privilege('authenticated','public.public_person_source_coordinates()','EXECUTE'))
  ||' koord='||(SELECT count(*) FROM k)
  ||' placement='||(SELECT count(*) FROM k WHERE k.provenance_kind='placement')
  ||' legacy='||(SELECT count(*) FROM k WHERE k.provenance_kind='legacy_external_id')
  ||' fakta='||(SELECT count(*) FROM f)
  ||' bundet='||(SELECT count(*) FROM f WHERE f.record_ref IS NOT NULL)
  ||' import='||(SELECT count(*) FROM f WHERE f.record_ref IS NULL AND f.source_id IS NOT NULL)
  ||' ingen_kilde='||(SELECT count(*) FROM f WHERE f.record_ref IS NULL AND f.source_id IS NULL)
  ||' uden_narrativ='||(SELECT count(DISTINCT f.person_id) FROM f
                         WHERE NOT EXISTS (SELECT 1 FROM public.narrative n
                                            WHERE n.subjekt_type='person' AND n.subjekt_id=f.person_id))
  ||' udfald_i_alt='||(SELECT count(*) FROM prom WHERE prom.record_ref IS NULL)
  ||' udfald_publicering='||(SELECT count(*) FROM prom WHERE prom.record_ref IS NULL AND prom.b14 AND prom.b2);
\else
SELECT 'C2B11_MAAL funktioner='||:fn_n;
\endif
COMMIT;
