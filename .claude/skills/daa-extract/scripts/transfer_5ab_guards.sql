-- Værn for 5a+5b-overførslen (plan B1 Task 2; spec §6.2 »Værn for nye personer« og »#244-værn«). Læse-kun, som ejer.
--   person_create_elements: elementer i relation_person_create_input(src) (skal være 0; beslutning 8)
--   ordinal_correction_rows: rækker i marriage_ordinal_correction_input(src) (skal være 0 i arbejdskørslen)
--   ordinal_book_mismatch:   gældende ægtefælleparter, hvis nummer modsiger bogens »g. N°« (relation_book_ordinal); en part
--                            uden persona har intet nummer og modsiger intet (som serverens ORDINAL_BOOK_MISMATCH)
--   book_ordinal_match:      {n_match, n_total} for gældende ægteskaber med bogens »N°«: bogens = serverens nummer
-- Brug: psql -v src=<kilde> -f transfer_5ab_guards.sql ⇒ én linje »daa.transfer_5ab_guards=<json>«.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SET LOCAL search_path TO pg_catalog;
SET LOCAL TimeZone='UTC';
SET LOCAL row_security=off;
WITH m AS (
  SELECT ic.interpretation_key k, private.relation_book_ordinal(ic.value->>'raw') book,
         (SELECT mo.marriage_ordinal FROM private.relation_marriage_ordinals(co.occurrence_id) mo
           WHERE mo.interpretation_key=ic.interpretation_key) server
    FROM private.interpretation_current ic
    JOIN private.interpretation_observation io ON io.interpretation_id=ic.id AND io.evidence_role='supporting' AND io.ordinal=1
    JOIN private.clause_observation_current co ON co.id=io.observation_id
   WHERE ic.source_id=:'src'::bigint AND ic.predicate='relation.marriage' AND ic.status<>'rejected'
)
SELECT 'daa.transfer_5ab_guards='||jsonb_build_object(
  'person_create_elements',
    (SELECT count(*) FROM jsonb_object_keys(private.relation_person_create_input(:'src'::bigint)->'authorized_elements')),
  'ordinal_correction_rows', jsonb_array_length(private.marriage_ordinal_correction_input(:'src'::bigint)->'rows'),
  'ordinal_book_mismatch',
    (SELECT count(*) FROM m JOIN private.interpretation_party_current pc ON pc.interpretation_key=m.k AND pc.party_role='spouse'
      WHERE m.book IS NOT NULL AND pc.marriage_ordinal IS NOT NULL AND pc.marriage_ordinal<>m.book),
  'book_ordinal_match', jsonb_build_object(
    'n_match', (SELECT count(*) FROM m WHERE m.book IS NOT NULL AND m.book=m.server),
    'n_total', (SELECT count(*) FROM m WHERE m.book IS NOT NULL)))::text;
COMMIT;
