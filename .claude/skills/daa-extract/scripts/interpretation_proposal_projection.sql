-- Laese-kun fortolkningsforslag-projektion, ejer-delen (issue 196). Udgaveneutral.
-- Koeres af interpretation_proposal_projection.psql i en READ ONLY + REPEATABLE READ-
-- transaktion efter set_config af daa.interpretation_projection_source_id.
-- Output: kun id'er, noegler, praedikater, hashes, taellinger, statusser og booleans.
-- Ingen kildetekst og ingen claim-vaerdi forlader databasen.
-- Detaljerede raekker hashes med lukkede jsonb-projektioner gennem
-- private.interpretation_proposal_canonical_json_sha256 (aldrig row::text).
-- Hele-tabel-aggregaterne (upstream/neutral/promotion) bruger x::text under de
-- fastlaaste sessionsindstillinger, som guarden asserterer, ligesom klausul-projektionen.
-- Guard-fejl rejses som tekst-til-integer-cast af en ikke-konstant streng.

-- Rolle-guard foerst: som anon ville privilegietjekket paa private.* afbryde med en
-- unavngivet fejl foer guard-CTE'en evalueres.
SELECT CASE
  WHEN NOT has_schema_privilege('private', 'USAGE')
    OR NOT has_table_privilege('private.interpretation', 'SELECT')
    THEN ('INTERPRETATION_PROJECTION_NOT_OWNER:' || current_user)::int
  ELSE 1 END AS owner_guard \gset

WITH guard AS (
  SELECT CASE
    WHEN nullif(current_setting('daa.interpretation_projection_source_id', true), '') IS NULL
      THEN ('INTERPRETATION_PROJECTION_SOURCE_ID_MISSING:' || coalesce(current_setting('daa.interpretation_projection_source_id', true), ''))::int
    WHEN current_setting('transaction_read_only') <> 'on'
      THEN ('INTERPRETATION_PROJECTION_NOT_READ_ONLY:' || current_setting('transaction_read_only'))::int
    WHEN current_setting('transaction_isolation') <> 'repeatable read'
      THEN ('INTERPRETATION_PROJECTION_NOT_REPEATABLE_READ:' || current_setting('transaction_isolation'))::int
    WHEN current_setting('TimeZone') <> 'UTC' OR current_setting('DateStyle') <> 'ISO, YMD'
      OR current_setting('IntervalStyle') <> 'postgres' OR current_setting('extra_float_digits') <> '1'
      OR current_setting('bytea_output') <> 'hex'
      THEN ('INTERPRETATION_PROJECTION_SESSION_SETTINGS_INVALID:' || current_setting('TimeZone'))::int
    ELSE 1 END AS ok,
    nullif(current_setting('daa.interpretation_projection_source_id', true), '')::bigint AS source_id
), records AS (
  SELECT r.id, r.record_key FROM private.source_record r JOIN guard g ON g.ok = 1 AND r.source_id = g.source_id
), accepted AS (
  SELECT r.record_key, a.occurrence_id FROM records r
  JOIN private.source_record_anchor_current a ON a.source_record_id = r.id AND a.decision_status = 'accepted'
), bound AS (
  SELECT r.record_key, p.narrative_id, p.status FROM records r
  JOIN private.narrative_record_publication p ON p.source_record_id = r.id
), source_runs AS (
  SELECT er.* FROM private.extraction_run er JOIN guard g ON g.ok = 1 AND er.source_id = g.source_id
), clause_obs AS (
  -- Klausul-observationer fra kildens egne koersler, med den accepterede post de hoerer til.
  SELECT o.id, o.clause_ordinal, ac.record_key
  FROM private.source_observation o
  JOIN source_runs r ON r.id = o.extraction_run_id
  LEFT JOIN accepted ac ON ac.occurrence_id = o.occurrence_id
  WHERE o.observation_kind = 'clause'
), clause_rows AS (
  SELECT d.observation_id, d.version, jsonb_build_object(
    'observation_id', d.observation_id,
    'record_key', c.record_key,
    'clause_ordinal', c.clause_ordinal,
    'version', d.version,
    'disposition', d.disposition,
    'decided_by_kind', d.decided_by_kind,
    'evidence_batch_id', d.evidence ->> 'batch_id',
    'evidence_extraction_run_id', d.evidence ->> 'extraction_run_id',
    'evidence_element_id', d.evidence ->> 'element_id',
    'evidence_manifest_sha256', d.evidence ->> 'manifest_sha256',
    'row_sha256', private.interpretation_proposal_canonical_json_sha256(private.interpretation_proposal_disposition_receipt(d))
  ) AS row
  FROM private.clause_disposition d JOIN clause_obs c ON c.id = d.observation_id
), interpretation_src AS (
  SELECT i.* FROM private.interpretation i JOIN guard g ON g.ok = 1 AND i.source_id = g.source_id
), link_rows AS (
  SELECT io.interpretation_id, io.ordinal, jsonb_build_object(
    'interpretation_id', io.interpretation_id,
    'observation_id', io.observation_id,
    'evidence_role', io.evidence_role,
    'link_ordinal', io.ordinal,
    'record_key', ac.record_key,
    'clause_ordinal', o.clause_ordinal,
    'verbatim_sha256', encode(pg_catalog.sha256(convert_to(o.verbatim_text, 'UTF8')), 'hex'),
    'row_sha256', private.interpretation_proposal_canonical_json_sha256(private.interpretation_proposal_link_receipt(io))
  ) AS row, ac.record_key, o.clause_ordinal,
  encode(pg_catalog.sha256(convert_to(o.verbatim_text, 'UTF8')), 'hex') AS verbatim_sha256
  FROM private.interpretation_observation io
  JOIN interpretation_src i ON i.id = io.interpretation_id
  JOIN private.source_observation o ON o.id = io.observation_id
  LEFT JOIN accepted ac ON ac.occurrence_id = o.occurrence_id
), interpretation_keyed AS (
  -- Post-noegle og citerede klausuler genskabes fra linkene, saa noegle-guarden kan
  -- genberegne interpretation_key med den samme SQL-autoritet som writeren.
  SELECT i AS irow,
    (SELECT CASE WHEN count(DISTINCT l.record_key) = 1 THEN min(l.record_key) END FROM link_rows l WHERE l.interpretation_id = i.id) AS record_key,
    (SELECT jsonb_agg(jsonb_build_object('ordinal', l.clause_ordinal, 'verbatim_sha256', l.verbatim_sha256) ORDER BY l.ordinal)
       FROM link_rows l WHERE l.interpretation_id = i.id) AS cited
  FROM private.interpretation i JOIN guard g ON g.ok = 1 AND i.source_id = g.source_id
), interpretation_rows AS (
  SELECT (k.irow).interpretation_key AS interpretation_key, (k.irow).version AS version, jsonb_build_object(
    'interpretation_id', (k.irow).id,
    'interpretation_key', (k.irow).interpretation_key,
    'version', (k.irow).version,
    'status', (k.irow).status,
    'record_key', k.record_key,
    'predicate', (k.irow).predicate,
    'interpretation_kind', (k.irow).interpretation_kind,
    'schema_version', (k.irow).schema_version,
    'derivation_kind', (k.irow).derivation_kind,
    'method', (k.irow).method,
    'confidence', (k.irow).confidence::text,
    'persona_bound', (k.irow).source_persona_id IS NOT NULL,
    'extraction_run_id', (k.irow).extraction_run_id,
    'supersedes_id', (k.irow).supersedes_id,
    'value_sha256', private.interpretation_proposal_canonical_json_sha256((k.irow).value),
    'key_material_sha256', CASE WHEN k.record_key IS NOT NULL AND k.cited IS NOT NULL THEN
      private.interpretation_proposal_key_material_sha256((k.irow).source_id, k.record_key, (k.irow).predicate, k.cited, (k.irow).value) END,
    'key_matches', coalesce(k.record_key IS NOT NULL AND k.cited IS NOT NULL
      AND (k.irow).interpretation_key = private.interpretation_proposal_key((k.irow).source_id, k.record_key, (k.irow).predicate, k.cited, (k.irow).value), false),
    'row_sha256', private.interpretation_proposal_canonical_json_sha256(private.interpretation_proposal_interpretation_receipt(k.irow))
  ) AS row
  FROM interpretation_keyed k
), run_rows AS (
  SELECT r.id, jsonb_build_object(
    'run_id', r.id,
    'run_key', r.run_key,
    'schema_version', r.schema_version,
    'extractor_version', r.extractor_version,
    'profile_version', r.profile_version,
    'input_sha256', r.input_sha256,
    'row_sha256', private.interpretation_proposal_canonical_json_sha256(jsonb_build_object(
      'id', r.id, 'source_id', r.source_id, 'run_key', r.run_key, 'schema_version', r.schema_version,
      'extractor_version', r.extractor_version, 'profile_version', r.profile_version,
      'input_sha256', r.input_sha256,
      'manifest_sha256', encode(pg_catalog.sha256(convert_to(r.manifest::text, 'UTF8')), 'hex'),
      'created_at', to_char(r.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')))
  ) AS row
  FROM source_runs r
), source_batches AS (
  SELECT b.* FROM private.reimport_batch b JOIN guard g ON g.ok = 1 AND b.source_id = g.source_id
), event_base AS (
  SELECT e.*, jsonb_build_object(
    'id', e.id, 'batch_id', e.batch_id, 'element_id', e.element_id, 'operation', e.operation,
    'source_record_key', e.source_record_key, 'canonical_person_id', e.canonical_person_id,
    'payload_sha256', encode(pg_catalog.sha256(convert_to(e.payload::text, 'UTF8')), 'hex'),
    'before_sha256', e.before_sha256, 'after_sha256', e.after_sha256,
    'created_at', to_char(e.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')) AS closed
  FROM private.reimport_event e JOIN source_batches b ON b.id = e.batch_id
), proposal_event_rows AS (
  SELECT e.id, jsonb_build_object(
    'event_id', e.id,
    'batch_id', e.batch_id,
    'element_id', e.element_id,
    'source_record_key', e.source_record_key,
    'run_id', e.payload ->> 'run_id',
    'runner_manifest_sha256', e.payload ->> 'runner_manifest_sha256',
    'model_version', e.payload ->> 'model_version',
    'prompt_version', e.payload ->> 'prompt_version',
    'claim_count', CASE WHEN jsonb_typeof(e.payload -> 'claims') = 'array' THEN jsonb_array_length(e.payload -> 'claims') END,
    'result_receipt', e.payload -> 'result_receipt',
    'result_receipt_sha256', CASE WHEN e.payload ? 'result_receipt'
      THEN private.interpretation_proposal_canonical_json_sha256(e.payload -> 'result_receipt') END,
    'before_sha256', e.before_sha256,
    'after_sha256', e.after_sha256,
    'row_sha256', private.interpretation_proposal_canonical_json_sha256(e.closed)
  ) AS row
  FROM event_base e WHERE e.operation = 'interpretation_proposal'
), reversal_event_rows AS (
  SELECT e.id, jsonb_build_object(
    'event_id', e.id,
    'batch_id', e.batch_id,
    'element_id', e.element_id,
    'source_record_key', e.source_record_key,
    'before_sha256', e.before_sha256,
    'after_sha256', e.after_sha256,
    'row_sha256', private.interpretation_proposal_canonical_json_sha256(e.closed)
  ) AS row
  FROM event_base e WHERE e.operation = 'reversal'
), authorization_rows AS (
  SELECT a.id, jsonb_build_object(
    'authorization_id', a.id,
    'operation', a.operation,
    'status', a.status,
    'consumed', a.consumed_at IS NOT NULL,
    'manifest_sha256', a.manifest_sha256,
    'preview_sha256', a.preview_sha256,
    'profile_id', a.profile_id,
    'profile_sha256', a.profile_sha256,
    'principal_id', a.principal_id,
    'expected_counts', a.expected_counts,
    'authorized_elements_sha256', encode(pg_catalog.sha256(convert_to(a.authorized_elements::text, 'UTF8')), 'hex'),
    'authorized_element_ids', coalesce((SELECT jsonb_agg(k ORDER BY k COLLATE "C") FROM jsonb_object_keys(a.authorized_elements) k), '[]'::jsonb),
    'row_sha256', private.interpretation_proposal_canonical_json_sha256(jsonb_build_object(
      'id', a.id, 'operation', a.operation, 'manifest_sha256', a.manifest_sha256, 'preview_sha256', a.preview_sha256,
      'database_identity_sha256', encode(pg_catalog.sha256(convert_to(a.database_identity, 'UTF8')), 'hex'),
      'source_id', a.source_id, 'expected_counts', a.expected_counts,
      'authorized_elements_sha256', encode(pg_catalog.sha256(convert_to(a.authorized_elements::text, 'UTF8')), 'hex'),
      'principal_id', a.principal_id, 'nonce', a.nonce, 'status', a.status,
      'profile_id', a.profile_id, 'profile_sha256', a.profile_sha256,
      'expires_at', to_char(a.expires_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'consumed_at', CASE WHEN a.consumed_at IS NULL THEN NULL ELSE to_char(a.consumed_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END,
      'created_at', to_char(a.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')))
  ) AS row
  FROM private.reimport_authorization a JOIN guard g ON g.ok = 1 AND a.source_id = g.source_id
), batch_rows AS (
  SELECT b.id, jsonb_build_object(
    'batch_id', b.id,
    'authorization_id', b.authorization_id,
    'status', b.status,
    'finalized', b.finalized_at IS NOT NULL,
    'manifest_sha256', b.manifest_sha256,
    'preview_sha256', b.preview_sha256,
    'profile_id', b.profile_id,
    'profile_sha256', b.profile_sha256,
    'principal_id', b.principal_id,
    'expected_counts', b.expected_counts,
    'observed_counts', b.observed_counts,
    'row_sha256', private.interpretation_proposal_canonical_json_sha256(jsonb_build_object(
      'id', b.id, 'authorization_id', b.authorization_id, 'manifest_sha256', b.manifest_sha256,
      'preview_sha256', b.preview_sha256, 'principal_id', b.principal_id, 'status', b.status,
      'expected_counts', b.expected_counts, 'observed_counts', b.observed_counts, 'source_id', b.source_id,
      'profile_id', b.profile_id, 'profile_sha256', b.profile_sha256,
      'created_at', to_char(b.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'finalized_at', CASE WHEN b.finalized_at IS NULL THEN NULL ELSE to_char(b.finalized_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END))
  ) AS row
  FROM source_batches b
), upstream AS (
  SELECT jsonb_build_object(
    'source_record', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_record x),
    'source_record_occurrence', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_record_occurrence x),
    'source_record_anchor_event', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_record_anchor_event x),
    'source_observation', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_observation x),
    'source_mention', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_mention x),
    'source_persona', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_persona x),
    'source_persona_mention', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_persona_mention x),
    'source_persona_identity', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_persona_identity x),
    'source_persona_identity_event', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_persona_identity_event x),
    'source_record_placement', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_record_placement x),
    'source_record_placement_decision', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_record_placement_decision x),
    'source_persona_placement', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_persona_placement x),
    'source_persona_placement_decision', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.source_persona_placement_decision x)
  ) AS hashes
), neutral AS (
  -- Kanonisk/offentlig flade + alt der tilhoerer ANDRE kilder.
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
    'narrative_record_publication', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.narrative_record_publication x),
    'interpretation_other_sources', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex')
      FROM private.interpretation x, guard g WHERE x.source_id <> g.source_id),
    'interpretation_observation_other_sources', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex')
      FROM private.interpretation_observation x JOIN private.interpretation i ON i.id = x.interpretation_id, guard g WHERE i.source_id <> g.source_id),
    'extraction_run_other_sources', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex')
      FROM private.extraction_run x, guard g WHERE x.source_id <> g.source_id),
    'clause_disposition_other_sources', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex')
      FROM private.clause_disposition x WHERE NOT EXISTS (SELECT 1 FROM clause_obs c WHERE c.id = x.observation_id)),
    'reimport_authorization_other_sources', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex')
      FROM private.reimport_authorization x, guard g WHERE x.source_id IS DISTINCT FROM g.source_id),
    'reimport_batch_other_sources', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex')
      FROM private.reimport_batch x, guard g WHERE x.source_id IS DISTINCT FROM g.source_id),
    'reimport_event_other_sources', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex')
      FROM private.reimport_event x WHERE NOT EXISTS (SELECT 1 FROM source_batches b WHERE b.id = x.batch_id)),
    'reimport_event_other_operations', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex')
      FROM private.reimport_event x JOIN source_batches b ON b.id = x.batch_id
      WHERE x.operation NOT IN ('interpretation_proposal', 'reversal'))
  ) AS hashes
), promotion AS (
  SELECT jsonb_build_object(
    'interpretation_promotion_rule', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.interpretation_promotion_rule x),
    'interpretation_promotion_rule_line', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.interpretation_promotion_rule_line x),
    'interpretation_promotion_batch', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.interpretation_promotion_batch x),
    'interpretation_promotion', (SELECT encode(pg_catalog.sha256(convert_to(coalesce(string_agg(x::text, E'\n' ORDER BY x::text COLLATE "C"), ''), 'UTF8')), 'hex') FROM private.interpretation_promotion x)
  ) AS hashes
)
SELECT jsonb_build_object(
  'schema_version', 'daa-interpretation-proposal-projection-v1',
  'snapshot_sha256', encode(pg_catalog.sha256(convert_to(txid_current_snapshot()::text, 'UTF8')), 'hex'),
  'source_id', g.source_id,
  'database_target_identity', jsonb_build_object(
    'database_name', current_database(),
    'system_identifier_sha256', encode(pg_catalog.sha256(convert_to((pg_control_system()).system_identifier::text, 'UTF8')), 'hex')),
  'source_records', (SELECT coalesce(jsonb_agg(jsonb_build_object('record_key', record_key) ORDER BY record_key COLLATE "C"), '[]'::jsonb) FROM records),
  'source_anchors', (SELECT coalesce(jsonb_agg(jsonb_build_object('record_key', record_key, 'occurrence_id', occurrence_id)
    ORDER BY record_key COLLATE "C", occurrence_id::text COLLATE "C"), '[]'::jsonb) FROM accepted),
  'narrative_bindings', (SELECT coalesce(jsonb_agg(jsonb_build_object('record_key', record_key, 'narrative_id', narrative_id, 'status', status)
    ORDER BY record_key COLLATE "C", narrative_id, status COLLATE "C"), '[]'::jsonb) FROM bound),
  'narrative_sha256', (SELECT coalesce(jsonb_agg(jsonb_build_object('narrative_id', n.id, 'sha256', encode(pg_catalog.sha256(convert_to(n.tekst, 'UTF8')), 'hex')) ORDER BY n.id), '[]'::jsonb)
    FROM public.narrative n WHERE n.id IN (SELECT narrative_id FROM bound)),
  'persons', (SELECT coalesce(jsonb_agg(jsonb_build_object('person_id', q.person_id) ORDER BY q.person_id), '[]'::jsonb)
    FROM (SELECT DISTINCT n.subjekt_id AS person_id FROM public.narrative n
          WHERE n.subjekt_type = 'person' AND n.id IN (SELECT narrative_id FROM bound)) q),
  'upstream_sha256', (SELECT private.interpretation_proposal_canonical_json_sha256(hashes) FROM upstream),
  'neutral_sha256', (SELECT private.interpretation_proposal_canonical_json_sha256(hashes) FROM neutral),
  'clauses', (SELECT coalesce(jsonb_agg(row ORDER BY observation_id::text COLLATE "C", version), '[]'::jsonb) FROM clause_rows),
  'interpretations', (SELECT coalesce(jsonb_agg(row ORDER BY interpretation_key::text COLLATE "C", version), '[]'::jsonb) FROM interpretation_rows),
  'interpretation_links', (SELECT coalesce(jsonb_agg(row ORDER BY interpretation_id::text COLLATE "C", ordinal), '[]'::jsonb) FROM link_rows),
  'extraction_runs', (SELECT coalesce(jsonb_agg(row ORDER BY id::text COLLATE "C"), '[]'::jsonb) FROM run_rows),
  'proposal_events', (SELECT coalesce(jsonb_agg(row ORDER BY id), '[]'::jsonb) FROM proposal_event_rows),
  'reversal_events', (SELECT coalesce(jsonb_agg(row ORDER BY id), '[]'::jsonb) FROM reversal_event_rows),
  'authorizations', (SELECT coalesce(jsonb_agg(row ORDER BY id::text COLLATE "C"), '[]'::jsonb) FROM authorization_rows),
  'batches', (SELECT coalesce(jsonb_agg(row ORDER BY id::text COLLATE "C"), '[]'::jsonb) FROM batch_rows),
  'promotion_sha256', (SELECT private.interpretation_proposal_canonical_json_sha256(hashes) FROM promotion)
)::text AS projection
FROM guard g WHERE g.ok = 1 \gset
