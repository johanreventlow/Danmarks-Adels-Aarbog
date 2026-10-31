-- Læse-kun måling til trin 6b's ceremonier B og C (runbook): kun antal og hashes, ingen tekst.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 [-v source_id=3] [-v profile_id=daa-1939-publication-v1] -f maal_trin6b.sql
-- Én linje:
--   T6B_MAAL tilstand=<foer|a|b|c> personas_k3=<n> identiteter_k3=<n> afventer=<n> k1_personas=<n> k1_identiteter=<n> k1_hash=<md5>
--   tilstand     afledt af DDL (ceremoni A), operationer og finaliserede batches:
--                  foer  publikationsprofilen eller writeren findes ikke (A ikke kørt)
--                  a     DDL på plads, ingen finaliseret publication_persona-batch
--                  b     finaliseret publication_persona-batch, ingen finaliseret publication_identity-batch
--                  c     finaliseret publication_identity-batch
--   personas_k3 / identiteter_k3   personas og identitetsrækker for kilden (kilde 3)
--   afventer     personas, private.persona_awaiting_control er sand for (venter på kontrol)
--   k1_*         kilde 1's (2018-20) personas og identiteter og en hash over dem; skal være uændret af B og C
\set QUIET on
\set ON_ERROR_STOP on
\if :{?source_id} \else \set source_id 3 \endif
\if :{?profile_id} \else \set profile_id daa-1939-publication-v1 \endif
BEGIN READ ONLY;
SELECT (to_regprocedure('private.write_publication_persona(uuid,text,jsonb)') IS NOT NULL
        AND to_regprocedure('private.persona_awaiting_control(uuid)') IS NOT NULL
        AND EXISTS (SELECT 1 FROM private.reimport_writer_profile WHERE source_id=:source_id AND profile_id=:'profile_id')) AS ddl \gset
WITH b AS (
  SELECT bb.id,
         EXISTS (SELECT 1 FROM private.reimport_event e WHERE e.batch_id=bb.id AND e.operation='publication_persona') AS pers,
         EXISTS (SELECT 1 FROM private.reimport_event e WHERE e.batch_id=bb.id AND e.operation='publication_identity') AS ident
    FROM private.reimport_batch bb
   WHERE bb.source_id=:source_id AND bb.profile_id=:'profile_id' AND bb.status IN ('finalized','activated')
), k1 AS (
  SELECT (SELECT count(*) FROM private.source_persona WHERE source_id=1) AS p,
         (SELECT count(*) FROM private.source_persona_identity i JOIN private.source_persona sp ON sp.id=i.source_persona_id
           WHERE sp.source_id=1) AS i,
         md5(coalesce((SELECT string_agg(concat_ws(':',sp.id,sp.persona_key,i.decision_status,i.canonical_person_id,i.version),'|'
                                         ORDER BY sp.id) FROM private.source_persona sp
                          LEFT JOIN private.source_persona_identity i ON i.source_persona_id=sp.id WHERE sp.source_id=1),'')) AS h
)
SELECT :'ddl'::boolean AS ddl,
       CASE WHEN NOT :'ddl'::boolean THEN 'foer'
            WHEN EXISTS (SELECT 1 FROM b WHERE ident) THEN 'c'
            WHEN EXISTS (SELECT 1 FROM b WHERE pers) THEN 'b'
            ELSE 'a' END AS tilstand,
       (SELECT count(*) FROM private.source_persona WHERE source_id=:source_id) AS personas,
       (SELECT count(*) FROM private.source_persona_identity i JOIN private.source_persona sp ON sp.id=i.source_persona_id
         WHERE sp.source_id=:source_id) AS identiteter,
       k1.p AS k1p, k1.i AS k1i, k1.h AS k1h FROM k1 \gset m_
\if :m_ddl
SELECT count(*) AS afventer FROM private.source_persona sp
 WHERE sp.source_id=:source_id AND private.persona_awaiting_control(sp.id) \gset m_
\else
\set m_afventer 0
\endif
SELECT format('T6B_MAAL tilstand=%s personas_k3=%s identiteter_k3=%s afventer=%s k1_personas=%s k1_identiteter=%s k1_hash=%s',
              :'m_tilstand',:'m_personas',:'m_identiteter',:'m_afventer',:'m_k1p',:'m_k1i',:'m_k1h');
ROLLBACK;
