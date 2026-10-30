-- Læse-kun afhængighedsfil til kildetekst-revisionen (trin 6a, spec §4.4). Ingen tekst forlader basen: helpostens
-- gældende tekst hashes her, og resten er spænd, nøgler, hashes og antal.
-- Brug (som ejer; de private funktioner er revoked fra authenticated/service_role):
--   psql -X -At -v ON_ERROR_STOP=1 -v source_id=<id> -v profile_id=<revisionsprofil> \
--        -v record_keys='["I-9","I-11"]' -f source_text_revision_dependencies.sql > <0600-fil>
-- Én linje JSON:
--   {schema_version, source_id, profile_id, profile_sha256, helpost_kind,
--    records:[{record_key, helpost_status, rendition_content_sha256, char_from, char_to, text_id,
--              before_text_sha256, clause_set_seq, clause_set_sha256,
--              expected_superseded_keys, expected_binding_loss}]}
-- Pr. record er det præcis de mængder, writeren (private.write_source_text_revision) måler under sine låse:
--   helposten          private.record_helpost_status med profilens helpost-slags (én regel, spec §4.2);
--   before_text_sha256 sha256 af private.helpost_text_current (den gældende tekst, ikke basisteksten);
--   aktuelt sæt        max(clause_set_seq) blandt helpostens klausuler, som writeren; hash med private.clause_set_sha256;
--   nøgler             private.text_revision_dependents, sorteret som uuid;
--   bindingstab        private.text_revision_binding_set over nøglerne, {promotion_id,target_type} sorteret som uuid.
-- Afhængigheder, revisionen ikke understøtter, får text_revision_dependents/text_revision_binding_set til at fejle
-- (TEXT_REVISION_DEPENDENCY_UNSUPPORTED, TEXT_REVISION_TARGET_TYPE_UNSUPPORTED): hele filen fejler lukket for hele
-- batchen, som preflighten skal. En record uden ok-helpost får helpost_status (none/ambiguous/outside/missing) og
-- null-felter; manifest-byggeren afviser den.
\set QUIET on
\set ON_ERROR_STOP on
\if :{?source_id}
\else
\set source_id ''
\endif
\if :{?profile_id}
\else
\set profile_id ''
\endif
\if :{?record_keys}
\else
\set record_keys ''
\endif
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;
-- Guard-fejl rejses som tekst-til-integer-cast af en ikke-konstant streng (som klausul-projektionen), så planneren
-- ikke konstant-folder en gren, der ikke er valgt.
WITH guard AS (
  SELECT CASE
           WHEN nullif(:'source_id', '') IS NULL OR nullif(:'profile_id', '') IS NULL OR nullif(:'record_keys', '') IS NULL
             THEN ('TEXT_REVISION_DEPENDENCIES_ARGS_MISSING:' || current_setting('transaction_isolation'))::int
           WHEN current_setting('transaction_read_only') <> 'on'
             THEN ('TEXT_REVISION_DEPENDENCIES_NOT_READ_ONLY:' || current_setting('transaction_read_only'))::int
           WHEN jsonb_typeof(nullif(:'record_keys', '')::jsonb) <> 'array'
                OR jsonb_array_length(nullif(:'record_keys', '')::jsonb) = 0
                OR EXISTS (SELECT 1 FROM jsonb_array_elements(nullif(:'record_keys', '')::jsonb) k
                            WHERE jsonb_typeof(k) <> 'string' OR btrim(k #>> '{}') = '')
                OR (SELECT count(*) FROM jsonb_array_elements_text(nullif(:'record_keys', '')::jsonb))
                   <> (SELECT count(DISTINCT k) FROM jsonb_array_elements_text(nullif(:'record_keys', '')::jsonb) k)
             THEN ('TEXT_REVISION_DEPENDENCIES_RECORD_KEYS_INVALID:' || current_setting('transaction_isolation'))::int
           ELSE 1
         END AS ok
), profile AS (
  SELECT p.source_id, p.profile_id, p.profile_sha256, private.writer_config_helpost_kind(p.writer_config) AS helpost_kind
    FROM guard g
    JOIN private.reimport_writer_profile p ON g.ok = 1 AND p.source_id = nullif(:'source_id', '')::bigint AND p.profile_id = :'profile_id'
), profile_ok AS (
  -- Profilen skal findes; (source_id, profile_id) er primærnøglen, så der er højst én.
  SELECT CASE WHEN (SELECT count(*) FROM profile) <> 1
              THEN ('TEXT_REVISION_DEPENDENCIES_PROFILE_MISSING:' || current_setting('transaction_isolation'))::int ELSE 1 END AS ok
), keys AS (
  SELECT k AS record_key
    FROM profile_ok po, jsonb_array_elements_text(nullif(:'record_keys', '')::jsonb) k
   WHERE po.ok = 1
), helpost AS (
  SELECT k.record_key, sr.id AS record_id, h.status, h.observation_id
    FROM keys k
    CROSS JOIN profile pr
    LEFT JOIN private.source_record sr ON sr.source_id = pr.source_id AND sr.record_key = k.record_key
    LEFT JOIN LATERAL private.record_helpost_status(sr.id, pr.helpost_kind) h ON sr.id IS NOT NULL
), detail AS (
  SELECT hp.record_key,
         CASE WHEN hp.record_id IS NULL THEN 'missing' ELSE hp.status END AS helpost_status,
         rd.content_sha256 AS rendition_content_sha256, ob.char_from, ob.char_to,
         t.text_id, CASE WHEN ob.id IS NOT NULL THEN encode(extensions.digest(t.verbatim_text, 'sha256'), 'hex') END AS before_text_sha256,
         s.seq AS clause_set_seq,
         CASE WHEN s.seq IS NOT NULL THEN private.clause_set_sha256(ob.id, s.seq) END AS clause_set_sha256,
         d.keys, ob.id AS observation_id
    FROM helpost hp
    LEFT JOIN private.source_observation ob ON ob.id = hp.observation_id AND hp.status = 'ok'
    LEFT JOIN private.source_record_occurrence o ON o.id = ob.occurrence_id
    LEFT JOIN private.source_rendition rd ON rd.id = o.rendition_id
    LEFT JOIN LATERAL private.helpost_text_current(ob.id) t ON ob.id IS NOT NULL
    LEFT JOIN LATERAL (
      -- Det aktuelle sæt som writeren bestemmer det: højeste clause_set_seq blandt helpostens klausuler.
      SELECT max(coalesce(c.clause_set_seq, 1)) AS seq
        FROM private.source_observation c
       WHERE c.parent_observation_id = ob.id AND c.observation_kind = 'clause'
    ) s ON ob.id IS NOT NULL
    LEFT JOIN LATERAL (
      SELECT coalesce(array_agg(x.interpretation_key ORDER BY x.interpretation_key), '{}'::uuid[]) AS keys
        FROM private.text_revision_dependents(ob.id) x
    ) d ON ob.id IS NOT NULL
), measured AS (
  SELECT de.*, b.bindings
    FROM detail de
    LEFT JOIN LATERAL (
      SELECT coalesce(jsonb_agg(jsonb_build_object('promotion_id', bs.promotion_id, 'target_type', bs.target_type)
                                ORDER BY bs.promotion_id), '[]'::jsonb) AS bindings
        FROM private.text_revision_binding_set(de.keys) bs
    ) b ON de.observation_id IS NOT NULL
)
SELECT jsonb_build_object(
         'schema_version', 'source-text-revision-dependencies-v1',
         'source_id', pr.source_id, 'profile_id', pr.profile_id, 'profile_sha256', pr.profile_sha256,
         'helpost_kind', pr.helpost_kind,
         'records', (SELECT jsonb_agg(jsonb_build_object(
                        'record_key', m.record_key, 'helpost_status', m.helpost_status,
                        'rendition_content_sha256', m.rendition_content_sha256,
                        'char_from', m.char_from, 'char_to', m.char_to, 'text_id', m.text_id,
                        'before_text_sha256', m.before_text_sha256,
                        'clause_set_seq', m.clause_set_seq, 'clause_set_sha256', m.clause_set_sha256,
                        'expected_superseded_keys',
                          CASE WHEN m.observation_id IS NOT NULL THEN to_jsonb(m.keys) END,
                        'expected_binding_loss', m.bindings)
                      ORDER BY m.record_key COLLATE "C")
                       FROM measured m))::text
  FROM profile_ok po
  LEFT JOIN profile pr ON true
 WHERE po.ok = 1;
ROLLBACK;
