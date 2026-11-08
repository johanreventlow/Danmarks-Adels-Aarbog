-- Trin 6c-3 (spec 2026-11-07-trin6c3-a6b-resten-design.md §4.5; plan Task 5): basens id → nøgle-kort til
-- tekstrevision_afstemning.py (`afgraens`, `kortsvar`, `oversaet`). Læse-kun.
-- interpretation.id er tilfældigt pr. base; kortet oversætter kontrolmodellens plan (id'er) til interpretation_key +
-- version og personaens persona_key + kanoniske person (beslutningsgrundlaget), så svarene kan bæres fra stand-in'en
-- til prod uden id'er. Kun de gældende `proposed` forslag i kilden (kontrolmodellens rækker) og kildens personas.
-- Udskriver kun id'er, nøgler, versioner, persona_key'er og person-id'er — ingen værdier eller tekst.
-- Kørsel (ejerforbindelse): psql -X -v ON_ERROR_STOP=1 -v source=<kilde> -f tekstrevision_idkort.sql > idkort.json
\set ON_ERROR_STOP on
\set QUIET on
\pset format unaligned
\pset tuples_only on
BEGIN READ ONLY;
SELECT jsonb_build_object(
  'contract','tekstrevision-idkort-v1',
  'source_id',(:'source')::bigint,
  'interpretations',coalesce((
    SELECT jsonb_agg(jsonb_build_object('id',ic.id::text,'interpretation_key',ic.interpretation_key::text,
                                        'version',ic.version) ORDER BY ic.interpretation_key::text COLLATE "C")
      FROM private.interpretation_current ic
     WHERE ic.source_id=(:'source')::bigint AND ic.status='proposed'),'[]'::jsonb),
  'personas',coalesce((
    SELECT jsonb_agg(jsonb_build_object('id',sp.id::text,'persona_key',sp.persona_key,
                                        'canonical_person_id',CASE WHEN i.decision_status='accepted'
                                                                   THEN i.canonical_person_id END,
                                        'identity_version',i.version) ORDER BY sp.id::text COLLATE "C")
      FROM private.source_persona sp
      LEFT JOIN private.source_persona_identity i ON i.source_persona_id=sp.id
     WHERE sp.source_id=(:'source')::bigint),'[]'::jsonb)) AS idkort;
ROLLBACK;
