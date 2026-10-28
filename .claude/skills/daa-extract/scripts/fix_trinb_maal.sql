-- Læse-kun måling til review trin B (plan 2026-10-27-review-trin-b-ddl.md, T0): kun antal, ingen tekst om personer.
-- Én linje: TRINB_MAAL ikke_afklaret=<a> ufor_null=<n> ufor_false=<n> relationer=<n> uden_family_id=<n> ubundne=<n> afvigere=<n>
--   ikke_afklaret   konklusioner på de cachede faktatyper (navn/fødsel/død/titel) med status ≠ 'afklaret' (NULL talt med; T4)
--   ufor_null       påstande med uforanderlig NULL (T3's vagt behandler NULL som sand)
--   ufor_false      redaktørens egne påstande (kan fortsat slettes)
--   relationer      accepterede relation.marriage/relation.parent; uden_family_id og ubundne er delmængder (T1)
--   afvigere        accepterede relationer, hvis bindingstilstand peger på en anden familie end afgørelsens
-- ikke_afklaret, ufor_null og afvigere skal være 0 før og efter ceremonien (T0 2026-10-27: 0/0/0).
BEGIN READ ONLY;
WITH rel AS (
  SELECT ic.id, ic.decision_evidence ? 'family_id' AS har_fid, (ic.decision_evidence->>'family_id')::bigint AS fid,
         EXISTS (SELECT 1 FROM private.interpretation_promotion x WHERE x.interpretation_id=ic.id AND x.target_type='family') AS bundet
    FROM private.interpretation_current ic
   WHERE ic.status='accepted' AND ic.predicate IN ('relation.marriage','relation.parent')
)
SELECT 'TRINB_MAAL'
       ||' ikke_afklaret='||(SELECT count(*) FROM public.conclusion c JOIN public.fact f ON c.target_type='fact' AND f.id=c.target_id
                               WHERE f.subjekt_type='person' AND f.faktatype IN ('navn','fødsel','død','titel')
                                 AND c.status IS DISTINCT FROM 'afklaret')
       ||' ufor_null='||(SELECT count(*) FROM public.assertion WHERE uforanderlig IS NULL)
       ||' ufor_false='||(SELECT count(*) FROM public.assertion WHERE uforanderlig IS FALSE)
       ||' relationer='||(SELECT count(*) FROM rel)
       ||' uden_family_id='||(SELECT count(*) FROM rel WHERE NOT har_fid)
       ||' ubundne='||(SELECT count(*) FROM rel WHERE NOT bundet)
       ||' afvigere='||(SELECT count(*) FROM (SELECT r.fid, private.relation_binding_state(r.id) AS st FROM rel r) s
                         WHERE s.st IS NOT NULL AND (s.st#>>'{family,family_id}')::bigint IS DISTINCT FROM s.fid);
ROLLBACK;
