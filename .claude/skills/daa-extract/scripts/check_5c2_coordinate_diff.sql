-- Læse-kun koordinatdiff til 5c-2 (plan 2026-10-29-5c2-b11-laeserflade.md, Task 3; spec §7): sammenligner
-- public_person_source_coordinates med person_source_coordinate_legacy over de offentlige personer. Kun id'er og
-- feltnavne. Legacy-labelen normaliseres til nr::text; provenance_kind er en ny kolonne og indgår ikke.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -f check_5c2_coordinate_diff.sql
-- Udskrift: én linje `person_id|source_id|felt` pr. afvigende felt (sorteret), og til sidst
--   C2B11_DIFF n=<antal felter> noegler=<ens|forskellige> genparitet=<ok|fejl>
--   genparitet=ok: samme (person, kilde)-nøgler, og kun kuld_label og printed_number_label afviger — dvs. de felter,
--   buildGenCoords projicerer (linje, slægtled lokal/gennem), og sorteringsheltallet er uændrede (træparitet).
\set QUIET on
\set ON_ERROR_STOP on
BEGIN READ ONLY;
WITH n AS MATERIALIZED (
  SELECT * FROM public.public_person_source_coordinates()
), g AS MATERIALIZED (
  SELECT l.person_id,l.source_id,l.legacy_line_code,l.printed_number,l.printed_number::text AS printed_number_label,
         l.generation_local,l.generation_global,l.kuld_label
    FROM public.person_source_coordinate_legacy l WHERE public.entitet_offentlig('person',l.person_id)
), par AS (
  SELECT g.person_id,g.source_id,v.felt
    FROM g JOIN n ON n.person_id=g.person_id AND n.source_id=g.source_id
   CROSS JOIN LATERAL (VALUES
     ('legacy_line_code',g.legacy_line_code IS DISTINCT FROM n.legacy_line_code),
     ('printed_number',g.printed_number IS DISTINCT FROM n.printed_number),
     ('printed_number_label',g.printed_number_label IS DISTINCT FROM n.printed_number_label),
     ('generation_local',g.generation_local IS DISTINCT FROM n.generation_local),
     ('generation_global',g.generation_global IS DISTINCT FROM n.generation_global),
     ('kuld_label',g.kuld_label IS DISTINCT FROM n.kuld_label)) v(felt,afviger)
   WHERE v.afviger
), nk AS (
  SELECT count(*) AS d FROM (
    (SELECT person_id,source_id FROM g EXCEPT SELECT person_id,source_id FROM n)
    UNION ALL
    (SELECT person_id,source_id FROM n EXCEPT SELECT person_id,source_id FROM g)) x
)
SELECT txt FROM (
  SELECT 0 AS o,par.person_id,par.source_id,par.felt,par.person_id||'|'||par.source_id||'|'||par.felt AS txt FROM par
  UNION ALL
  SELECT 1,NULL,NULL,NULL,
         'C2B11_DIFF n='||(SELECT count(*) FROM par)
         ||' noegler='||CASE WHEN (SELECT d FROM nk)=0 THEN 'ens' ELSE 'forskellige' END
         ||' genparitet='||CASE WHEN (SELECT d FROM nk)=0
                                 AND NOT EXISTS (SELECT 1 FROM par WHERE par.felt NOT IN ('kuld_label','printed_number_label'))
                            THEN 'ok' ELSE 'fejl' END
) x ORDER BY o,person_id,source_id,felt;
ROLLBACK;
