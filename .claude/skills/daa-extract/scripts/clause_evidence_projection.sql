-- Laese-kun klausul-projektion, ejer-delen (spec 11.1, vej C, issue 195). Udgaveneutral.
-- Koeres af clause_evidence_projection.psql i en READ ONLY + REPEATABLE READ-transaktion
-- efter set_config af daa.projection_source_id. Returnerer kolonnen projection (tekst).
-- Ingen kildetekst forlader databasen: al tekst hashes her med pg_catalog.sha256.
-- Neutralitet maales paa hele raekker pr. tabel, ikke paa antal.
-- Guard-fejl rejses som tekst-til-integer-cast af en ikke-konstant streng, saa
-- planneren ikke kan konstant-folde den.
-- Gengivelsen af x::text afhaenger af TimeZone, DateStyle, IntervalStyle og
-- extra_float_digits. Driveren fastlaaser dem med SET LOCAL foer denne fil koeres,
-- og guarden herunder asserterer dem, saa foer- og efter-koersler i forskellige
-- shells ikke kan give falsk drift alene fordi gengivelsen skiftede.
WITH guard AS (
  SELECT
    CASE
      WHEN nullif(current_setting('daa.projection_source_id', true), '') IS NULL
        THEN ('CLAUSE_PROJECTION_SOURCE_ID_MISSING:' || coalesce(current_setting('daa.projection_source_id', true), ''))::int
      WHEN current_setting('transaction_read_only') <> 'on'
        THEN ('CLAUSE_PROJECTION_NOT_READ_ONLY:' || current_setting('transaction_read_only'))::int
      WHEN current_setting('transaction_isolation') <> 'repeatable read'
        THEN ('CLAUSE_PROJECTION_NOT_REPEATABLE_READ:' || current_setting('transaction_isolation'))::int
      WHEN current_setting('TimeZone') <> 'UTC'
        OR current_setting('DateStyle') <> 'ISO, YMD'
        OR current_setting('IntervalStyle') <> 'postgres'
        OR current_setting('extra_float_digits') <> '1'
        THEN ('CLAUSE_PROJECTION_SESSION_SETTINGS_INVALID:' || current_setting('TimeZone'))::int
      ELSE 1
    END AS ok,
    nullif(current_setting('daa.projection_source_id', true), '')::bigint AS source_id
), records AS (
  SELECT r.id, r.record_key
  FROM private.source_record r
  JOIN guard g ON g.ok = 1 AND r.source_id = g.source_id
), accepted AS (
  SELECT r.record_key, a.occurrence_id, o.occurrence_key
  FROM records r
  JOIN private.source_record_anchor_current a ON a.source_record_id = r.id AND a.decision_status = 'accepted'
  JOIN private.source_record_occurrence o ON o.id = a.occurrence_id
), bound AS (
  SELECT r.record_key, p.narrative_id, p.status
  FROM records r
  JOIN private.narrative_record_publication p ON p.source_record_id = r.id
), clause_rows AS (
  SELECT o.occurrence_key, c.clause_ordinal, jsonb_build_object(
    'observation_id', c.id::text,
    'row_sha256', encode(pg_catalog.sha256(convert_to(c::text, 'UTF8')), 'hex'),
    'disposition_history_sha256', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(h::text, E'\n' ORDER BY h::text COLLATE "C"), ''), 'UTF8')), 'hex')
                                   FROM private.clause_disposition h WHERE h.observation_id = c.id),
    'run_id', run.id::text,
    'run_matches_profile', coalesce(run.schema_version = wp.writer_config ->> 'schema_version'
                                    AND run.extractor_version = wp.writer_config ->> 'extractor_version'
                                    AND run.profile_version = wp.profile_version
                                    AND run.manifest ->> 'profile_sha256' = rb.profile_sha256, false),
    -- Laeser regelversionen fra den AKTUELLE disposition-evidens, saa en senere v2-disposition
    -- (menneskelig gennemgang, 4.5) goer dette false for en klausul der oprindeligt blev skrevet
    -- korrekt. For en frisk clause_evidence-koersel er version 1 ogsaa et krav.
    'extraction_method_matches_profile', coalesce(c.extraction_method = (wp.writer_config ->> 'observation_extraction_method')
                                                  || ':' || (d.evidence ->> 'clause_rules_version'), false),
    'record_key', ac.record_key,
    'occurrence_key', o.occurrence_key,
    'clause_ordinal', c.clause_ordinal,
    'char_from', c.char_from, 'char_to', c.char_to,
    'post_char_from', c.post_char_from, 'post_char_to', c.post_char_to,
    'classification', c.clause_classification,
    'flags', c.clause_flags,
    'verbatim_sha256', encode(pg_catalog.sha256(convert_to(c.verbatim_text, 'UTF8')), 'hex'),
    'parent_verbatim_sha256', encode(pg_catalog.sha256(convert_to(parent.verbatim_text, 'UTF8')), 'hex'),
    'disposition', d.disposition,
    'disposition_version', d.version,
    'decided_by_kind', d.decided_by_kind,
    'disposition_evidence', CASE WHEN d.decided_by_kind = 'machine' THEN jsonb_build_object(
      'batch_id', d.evidence -> 'batch_id',
      'element_id', d.evidence -> 'element_id',
      'manifest_sha256', d.evidence -> 'manifest_sha256',
      'clause_rules_version', d.evidence -> 'clause_rules_version') END,
    'disposition_evidence_keys', coalesce((SELECT jsonb_agg(k ORDER BY k COLLATE "C") FROM jsonb_object_keys(d.evidence) k), '[]'::jsonb),
    'extraction_method', c.extraction_method,
    'run_input_sha256', run.input_sha256,
    'run_batch_id', run.manifest ->> 'batch_id',
    'same_occurrence_as_parent', coalesce(parent.occurrence_id = c.occurrence_id, false),
    'parent_is_root', coalesce(parent.id IS NOT NULL AND parent.parent_observation_id IS NULL, false),
    'pages_match_parent', coalesce(parent.page_from = c.page_from AND parent.page_to = c.page_to, false),
    'quality_matches_parent', coalesce(parent.quality_status = c.quality_status, false)
  ) AS row
  FROM private.source_observation c
  JOIN private.extraction_run run ON run.id = c.extraction_run_id
  JOIN guard g ON g.ok = 1 AND run.source_id = g.source_id
  JOIN private.source_record_occurrence o ON o.id = c.occurrence_id
  LEFT JOIN accepted ac ON ac.occurrence_id = c.occurrence_id
  LEFT JOIN private.source_observation parent ON parent.id = c.parent_observation_id
  LEFT JOIN private.clause_disposition_current d ON d.observation_id = c.id
  LEFT JOIN private.reimport_batch rb ON rb.id::text = run.manifest ->> 'batch_id'
  LEFT JOIN private.reimport_writer_profile wp
    ON wp.source_id = rb.source_id AND wp.profile_id = rb.profile_id AND wp.profile_sha256 = rb.profile_sha256
  WHERE c.observation_kind = 'clause'
), event_rows AS (
  SELECT e.element_id, jsonb_build_object(
    'batch_id', b.id::text,
    'manifest_sha256', b.manifest_sha256,
    'batch_status', b.status,
    'profile_id', b.profile_id,
    'profile_sha256', b.profile_sha256,
    'row_sha256', encode(pg_catalog.sha256(convert_to(e::text, 'UTF8')), 'hex'),
    'element_id', e.element_id,
    'source_record_key', e.source_record_key
  ) AS row
  FROM private.reimport_event e
  JOIN private.reimport_batch b ON b.id = e.batch_id
  JOIN guard g ON g.ok = 1 AND b.source_id = g.source_id
  WHERE e.operation = 'clause_evidence'
), neutral AS (
  SELECT jsonb_build_object(
    'person', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.person x),
    'fact', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.fact x),
    'assertion', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.assertion x),
    'conclusion', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.conclusion x),
    'narrative', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.narrative x),
    'relation', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.relation x),
    'family_member', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.family_member x),
    'citation', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.citation x),
    'person_external_id', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM public.person_external_id x),
    'source_mention', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_mention x),
    'source_record', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_record x),
    'source_record_occurrence', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_record_occurrence x),
    'source_record_anchor_event', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_record_anchor_event x),
    'narrative_record_publication', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.narrative_record_publication x),
    'source_observation_non_clause', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_observation x WHERE x.observation_kind <> 'clause'),
    'source_observation_clause_other_sources', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex')
      FROM private.source_observation x JOIN private.extraction_run er ON er.id = x.extraction_run_id, guard g
      WHERE x.observation_kind = 'clause' AND er.source_id <> g.source_id),
    'clause_disposition_other_sources', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex')
      FROM private.clause_disposition x JOIN private.source_observation ob ON ob.id = x.observation_id
      JOIN private.extraction_run er ON er.id = ob.extraction_run_id, guard g
      WHERE er.source_id <> g.source_id)
  ) AS hashes
)
SELECT jsonb_build_object(
  'schema_version', 'daa-clause-evidence-projection-v1',
  'source_id', g.source_id,
  'database_target_identity', jsonb_build_object(
    'database_name', current_database(),
    'system_identifier_sha256', encode(pg_catalog.sha256(convert_to((pg_control_system()).system_identifier::text, 'UTF8')), 'hex')
  ),
  'source_records', (SELECT coalesce(jsonb_agg(jsonb_build_object('record_key', record_key) ORDER BY record_key COLLATE "C"), '[]'::jsonb) FROM records),
  'source_anchors', (SELECT coalesce(jsonb_agg(jsonb_build_object('record_key', record_key, 'occurrence_key', occurrence_key) ORDER BY record_key COLLATE "C", occurrence_key COLLATE "C"), '[]'::jsonb) FROM accepted),
  'narrative_bindings', (SELECT coalesce(jsonb_agg(jsonb_build_object('record_key', record_key, 'narrative_id', narrative_id, 'status', status) ORDER BY record_key COLLATE "C", narrative_id, status COLLATE "C"), '[]'::jsonb) FROM bound),
  'narrative_sha256', (SELECT coalesce(jsonb_agg(jsonb_build_object('narrative_id', n.id, 'sha256', encode(pg_catalog.sha256(convert_to(n.tekst, 'UTF8')), 'hex')) ORDER BY n.id), '[]'::jsonb)
                       FROM public.narrative n WHERE n.id IN (SELECT narrative_id FROM bound)),
  'persons', (SELECT coalesce(jsonb_agg(jsonb_build_object('person_id', q.person_id) ORDER BY q.person_id), '[]'::jsonb)
              FROM (SELECT DISTINCT n.subjekt_id AS person_id FROM public.narrative n
                    WHERE n.subjekt_type = 'person' AND n.id IN (SELECT narrative_id FROM bound)) q),
  'clauses', (SELECT coalesce(jsonb_agg(row ORDER BY occurrence_key COLLATE "C", clause_ordinal), '[]'::jsonb) FROM clause_rows),
  'clause_evidence_events', (SELECT coalesce(jsonb_agg(row ORDER BY element_id COLLATE "C"), '[]'::jsonb) FROM event_rows),
  'neutral_sha256', neutral.hashes
)::text AS projection
FROM guard g, neutral
WHERE g.ok = 1
