-- Maalidentitetens hash: sha256(database_name + linjeskift + sha256(system_identifier)).
-- Samme formel som target_sha256 i compare_clause_evidence_projection.py.
SELECT encode(pg_catalog.sha256(convert_to(
  current_database() || E'\n' ||
  encode(pg_catalog.sha256(convert_to((pg_control_system()).system_identifier::text, 'UTF8')), 'hex'),
  'UTF8')), 'hex') AS database_target_sha256
