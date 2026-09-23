-- SHA-256(database name + newline + SHA-256(system identifier)).
SELECT encode(pg_catalog.sha256(convert_to(
  current_database() || E'\n' ||
  encode(pg_catalog.sha256(convert_to(
    (pg_control_system()).system_identifier::text,'UTF8')),'hex'),
  'UTF8')),'hex') AS database_target_sha256;
