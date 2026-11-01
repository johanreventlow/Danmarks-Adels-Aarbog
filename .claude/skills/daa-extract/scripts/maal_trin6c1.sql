-- Læse-kun måling til trin 6c-1's ceremonier (runbook): kun antal og hashes, ingen id'er, navne eller tekst.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 [-v source_id=3] [-v publication_profile_id=daa-1939-publication-v1] -f maal_trin6c1.sql
--   (kør fra en mappe, scriptet selv ligger i)
-- Én linje:
--   T6C1_MAAL tilstand=<foer|a|b|c> forslag_k3=<n> poster_k3=<n> identiteter_k3=<n> afventer=<n> k1_forslag_hash=<sha256>
--   tilstand       foer  forslagswriteren nævner ikke record_helpost_observation (6c-1-DDL ikke kørt)
--                  a     DDL på plads, ingen forslag for kilden
--                  b     forslag for kilden, ingen finaliseret publication_identity-batch
--                  c     en finaliseret/aktiveret batch med publikationsprofilen (publication_profile_id) og en
--                        publication_identity-hændelse findes (C kørt; samme filter som maal_trin6b.sql)
--   forslag_k3     version 1-fortolkninger for kilden (kilde 3)
--   poster_k3      distinkte recordnøgler med en interpretation_proposal-hændelse i en finaliseret/aktiveret batch
--                  for kilden (en åben eller tilbageført batch tæller ikke)
--   identiteter_k3 personas for kilden med en accepteret identitet
--   afventer       personas for kilden, private.persona_awaiting_control er sand for (samme prædikat som maal_trin6b.sql)
--   k1_forslag_hash kilde 1's (2018-20) forslagsdigest (interpretation_transfer_digests.sql); skal være uændret af 6c-1
\set QUIET on
\set ON_ERROR_STOP on
\if :{?source_id} \else \set source_id 3 \endif
\if :{?publication_profile_id} \else \set publication_profile_id daa-1939-publication-v1 \endif
BEGIN READ ONLY;
SELECT coalesce((SELECT position('record_helpost_observation' IN p.prosrc)>0
                   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='private' AND p.proname='write_interpretation_proposal'
                  ORDER BY p.oid DESC LIMIT 1), false) AS ddl \gset
SELECT (SELECT count(*) FROM private.interpretation WHERE source_id=:source_id AND version=1) AS forslag,
       (SELECT count(DISTINCT e.source_record_key) FROM private.reimport_event e
          JOIN private.reimport_batch b ON b.id=e.batch_id
         WHERE b.source_id=:source_id AND b.status IN ('finalized','activated')
           AND e.operation='interpretation_proposal') AS poster,
       (SELECT count(*) FROM private.source_persona sp
         WHERE sp.source_id=:source_id
           AND EXISTS (SELECT 1 FROM private.source_persona_identity i
                        WHERE i.source_persona_id=sp.id AND i.decision_status='accepted')) AS identiteter,
       EXISTS (SELECT 1 FROM private.reimport_batch b
                WHERE b.source_id=:source_id AND b.status IN ('finalized','activated')
                  AND b.profile_id=:'publication_profile_id'
                  AND EXISTS (SELECT 1 FROM private.reimport_event e
                               WHERE e.batch_id=b.id AND e.operation='publication_identity')) AS ident_batch \gset m_
SELECT CASE WHEN NOT :'ddl'::boolean THEN 'foer'
            WHEN :'m_ident_batch'::boolean THEN 'c'
            WHEN :m_forslag>0 THEN 'b'
            ELSE 'a' END AS tilstand \gset m_
SELECT to_regprocedure('private.persona_awaiting_control(uuid)') IS NOT NULL AS har_kontrol \gset
\if :har_kontrol
SELECT count(*) AS afventer FROM private.source_persona sp
 WHERE sp.source_id=:source_id AND private.persona_awaiting_control(sp.id) \gset m_
\else
\set m_afventer 0
\endif
\set src 1
\o /dev/null
\ir interpretation_transfer_digests.sql
\o
SELECT current_setting('daa.transfer_digests')::jsonb->>'proposal_digest' AS k1_hash \gset m_
SELECT format('T6C1_MAAL tilstand=%s forslag_k3=%s poster_k3=%s identiteter_k3=%s afventer=%s k1_forslag_hash=%s',
              :'m_tilstand',:'m_forslag',:'m_poster',:'m_identiteter',:'m_afventer',:'m_k1_hash');
ROLLBACK;
