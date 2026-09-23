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
      THEN ('INTERPRETATION_PROJECTION_SESSION_SETTINGS_INVALID:' || current_setting('TimeZone'))::int
    ELSE 1 END AS ok,
    nullif(current_setting('daa.interpretation_projection_source_id', true), '')::bigint AS source_id
), records AS (
  SELECT r.id, r.record_key FROM private.source_record r JOIN guard g ON g.ok = 1 AND r.source_id = g.source_id
), accepted AS (
  SELECT r.record_key,a.occurrence_id,o.occurrence_key FROM records r
  JOIN private.source_record_anchor_current a ON a.source_record_id=r.id AND a.decision_status='accepted'
  JOIN private.source_record_occurrence o ON o.id=a.occurrence_id
), bound AS (
  SELECT r.record_key,p.narrative_id,p.status FROM records r
  JOIN private.narrative_record_publication p ON p.source_record_id=r.id
), interpretation_rows AS (
  SELECT i.* FROM private.interpretation i JOIN guard g ON g.ok=1 AND i.source_id=g.source_id
), link_rows AS (
  SELECT io.* FROM private.interpretation_observation io JOIN interpretation_rows i ON i.id=io.interpretation_id
), run_rows AS (
  SELECT er.* FROM private.extraction_run er JOIN guard g ON g.ok=1 AND er.source_id=g.source_id
), proposal_event_rows AS (
  SELECT e.*,b.profile_id,b.profile_sha256,b.status AS batch_status FROM private.reimport_event e
  JOIN private.reimport_batch b ON b.id=e.batch_id JOIN guard g ON g.ok=1 AND b.source_id=g.source_id
  WHERE e.operation='interpretation_proposal'
), authorization_rows AS (
  SELECT a.* FROM private.reimport_authorization a JOIN guard g ON g.ok=1 AND a.source_id=g.source_id
), batch_rows AS (
  SELECT b.* FROM private.reimport_batch b JOIN guard g ON g.ok=1 AND b.source_id=g.source_id
), clause_rows AS (
  SELECT d.* FROM private.clause_disposition d JOIN private.source_observation o ON o.id=d.observation_id
  JOIN run_rows r ON r.id=o.extraction_run_id WHERE o.observation_kind='clause'
), promotion_rows AS (
  SELECT p.* FROM private.interpretation_promotion p JOIN interpretation_rows i ON i.id=p.interpretation_id
)
SELECT jsonb_build_object(
  'schema_version','daa-interpretation-proposal-projection-v1',
  'snapshot_sha256',encode(extensions.digest(convert_to(txid_current_snapshot()::text,'UTF8'),'sha256'),'hex'),
  'source_id',g.source_id,
  'database_target_identity',jsonb_build_object('database_name',current_database(),'system_identifier_sha256',encode(extensions.digest(convert_to((pg_control_system()).system_identifier::text,'UTF8'),'sha256'),'hex')),
  'source_records',coalesce((SELECT jsonb_agg(jsonb_build_object('record_key',record_key) ORDER BY record_key COLLATE "C") FROM records),'[]'::jsonb),
  'source_anchors',coalesce((SELECT jsonb_agg(jsonb_build_object('record_key',record_key,'occurrence_id',occurrence_id)
    ORDER BY record_key COLLATE "C",occurrence_id::text COLLATE "C") FROM accepted),'[]'::jsonb),
  'narrative_bindings',coalesce((SELECT jsonb_agg(jsonb_build_object('record_key',record_key,'narrative_id',narrative_id,'status',status)
    ORDER BY record_key COLLATE "C",narrative_id,status COLLATE "C") FROM bound),'[]'::jsonb),
  'narrative_sha256',coalesce((SELECT jsonb_agg(jsonb_build_object('narrative_id',n.id,'sha256',encode(extensions.digest(convert_to(n.tekst,'UTF8'),'sha256'),'hex')) ORDER BY n.id)
    FROM public.narrative n WHERE n.id IN (SELECT narrative_id FROM bound)),'[]'::jsonb),
  'persons',coalesce((SELECT jsonb_agg(jsonb_build_object('person_id',person_id) ORDER BY person_id)
    FROM (SELECT DISTINCT n.subjekt_id AS person_id FROM public.narrative n WHERE n.subjekt_type='person' AND n.id IN (SELECT narrative_id FROM bound)) ids),'[]'::jsonb),
  'upstream_sha256',encode(extensions.digest(''::bytea,'sha256'),'hex'),'neutral_sha256',encode(extensions.digest(''::bytea,'sha256'),'hex'),
  'clauses',coalesce((SELECT jsonb_agg(jsonb_build_object('observation_id',d.observation_id,'version',d.version,'disposition',d.disposition,'row_sha256',private.interpretation_proposal_canonical_json_sha256(private.interpretation_proposal_disposition_receipt(d))) ORDER BY d.observation_id::text COLLATE "C",d.version) FROM clause_rows d),'[]'::jsonb),
  'interpretations',coalesce((SELECT jsonb_agg(jsonb_build_object('interpretation_id',i.id,'interpretation_key',i.interpretation_key,'version',i.version,'predicate',i.predicate,'value_sha256',private.interpretation_proposal_canonical_json_sha256(i.value),'row_sha256',private.interpretation_proposal_canonical_json_sha256(private.interpretation_proposal_interpretation_receipt(i)),'extraction_run_id',i.extraction_run_id) ORDER BY i.interpretation_key::text COLLATE "C",i.version) FROM interpretation_rows i),'[]'::jsonb),
  'interpretation_links',coalesce((SELECT jsonb_agg(jsonb_build_object('interpretation_id',l.interpretation_id,'observation_id',l.observation_id,'evidence_role',l.evidence_role,'ordinal',l.ordinal,'row_sha256',private.interpretation_proposal_canonical_json_sha256(private.interpretation_proposal_link_receipt(l))) ORDER BY l.interpretation_id::text COLLATE "C",l.ordinal) FROM link_rows l),'[]'::jsonb),
  'extraction_runs',coalesce((SELECT jsonb_agg(jsonb_build_object('run_id',r.id,'run_key',r.run_key,'input_sha256',r.input_sha256,'schema_version',r.schema_version,'extractor_version',r.extractor_version,'profile_version',r.profile_version) ORDER BY r.id::text COLLATE "C") FROM run_rows r),'[]'::jsonb),
  'proposal_events',coalesce((SELECT jsonb_agg(jsonb_build_object('event_id',e.id,'batch_id',e.batch_id,'element_id',e.element_id,'source_record_key',e.source_record_key,'result_receipt',e.payload->'result_receipt','after_sha256',e.after_sha256,'batch_status',e.batch_status,'profile_id',e.profile_id,'profile_sha256',e.profile_sha256) ORDER BY e.id) FROM proposal_event_rows e),'[]'::jsonb),
  'reversal_events','[]'::jsonb,
  'authorizations',coalesce((SELECT jsonb_agg(jsonb_build_object('authorization_id',a.id,'status',a.status,'manifest_sha256',a.manifest_sha256,'preview_sha256',a.preview_sha256,'profile_id',a.profile_id,'profile_sha256',a.profile_sha256,'expected_counts',a.expected_counts) ORDER BY a.id::text COLLATE "C") FROM authorization_rows a),'[]'::jsonb),
  'batches',coalesce((SELECT jsonb_agg(jsonb_build_object('batch_id',b.id,'authorization_id',b.authorization_id,'status',b.status,'manifest_sha256',b.manifest_sha256,'preview_sha256',b.preview_sha256,'profile_id',b.profile_id,'profile_sha256',b.profile_sha256,'expected_counts',b.expected_counts,'observed_counts',b.observed_counts) ORDER BY b.id::text COLLATE "C") FROM batch_rows b),'[]'::jsonb),
  'promotion_sha256',coalesce((SELECT encode(extensions.digest(convert_to(string_agg(p.id::text,E'\n' ORDER BY p.id::text COLLATE "C"),'UTF8'),'sha256'),'hex') FROM promotion_rows p),encode(extensions.digest(''::bytea,'sha256'),'hex')
))::text AS projection FROM guard g WHERE g.ok = 1 \gset
